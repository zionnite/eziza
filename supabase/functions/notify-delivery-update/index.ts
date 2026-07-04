import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { json } from '../_shared/cors.ts'

// Triggered by DB webhook on deliveries UPDATE (status changes only).
// Routes push notifications to the right party at each stage:
//   awaiting_pickup_confirm → customer  "Rider has arrived"
//   delivered               → customer  "Please confirm receipt"
//   confirmed               → rider     "Delivery confirmed, earnings credited"

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
)
const notifyUrl = `${Deno.env.get('SUPABASE_URL')}/functions/v1/send-notification`
const authHeader = `Bearer ${Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')}`

type Config = { recipientType: 'customer' | 'rider'; title: string; body: string }

const STATUS_CONFIGS: Record<string, Config> = {
  awaiting_pickup_confirm: {
    recipientType: 'customer',
    title: '📍 Rider Has Arrived',
    body: 'Your rider is at the pickup location — please confirm the handoff.',
  },
  delivered: {
    recipientType: 'customer',
    title: '🎉 Package Delivered!',
    body: 'Your package has arrived at its destination. Tap to confirm receipt.',
  },
  confirmed: {
    recipientType: 'rider',
    title: '✅ Delivery Confirmed',
    body: 'The customer confirmed receipt. Your earnings have been credited!',
  },
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok')

  try {
    const { record, old_record } = await req.json()
    const newStatus = record?.status as string | undefined
    const oldStatus = old_record?.status as string | undefined

    if (!newStatus || newStatus === oldStatus) {
      return json({ ok: true, reason: 'no status change' })
    }

    const config = STATUS_CONFIGS[newStatus]
    if (!config) return json({ ok: true, reason: `no notification for status: ${newStatus}` })

    let token: string | null = null

    if (config.recipientType === 'customer') {
      const customerId = record.customer_id as string | undefined
      if (!customerId) return json({ ok: true, reason: 'no customer_id' })

      const { data } = await supabase
        .from('device_tokens')
        .select('token')
        .eq('auth_user_id', customerId)
        .maybeSingle()
      token = data?.token ?? null
    } else {
      // Rider — look up auth_user_id from riders table
      const riderId = record.rider_id as string | undefined
      if (!riderId) return json({ ok: true, reason: 'no rider_id' })

      const { data: riderRow } = await supabase
        .from('riders')
        .select('auth_user_id')
        .eq('id', riderId)
        .maybeSingle()
      if (!riderRow?.auth_user_id) return json({ ok: true, reason: 'rider auth_user_id not found' })

      const { data } = await supabase
        .from('device_tokens')
        .select('token')
        .eq('auth_user_id', riderRow.auth_user_id)
        .maybeSingle()
      token = data?.token ?? null
    }

    if (!token) return json({ ok: true, reason: 'no device token on file' })

    const res = await fetch(notifyUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: authHeader },
      body: JSON.stringify({
        token,
        title: config.title,
        body: config.body,
        data: {
          type: 'delivery_update',
          delivery_id: record.id as string,
          status: newStatus,
        },
      }),
    })

    const resBody = await res.json()
    return json({ ok: res.ok, status: newStatus, fcm: resBody })
  } catch (err) {
    return json({ error: (err as Error).message }, 500)
  }
})
