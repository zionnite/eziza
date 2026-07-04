import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { json } from '../_shared/cors.ts'

// Triggered by DB webhook on delivery_bids UPDATE when status → 'accepted'.
// Notifies the winning rider or company that their bid was accepted.

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
)
const notifyUrl = `${Deno.env.get('SUPABASE_URL')}/functions/v1/send-notification`
const authHeader = `Bearer ${Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')}`

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok')

  try {
    const { record, old_record } = await req.json()

    // Only fire when bid transitions to accepted
    if (record?.status !== 'accepted' || old_record?.status === 'accepted') {
      return json({ ok: true, reason: 'not an acceptance transition' })
    }

    const riderId   = record.rider_id   as string | undefined
    const companyId = record.company_id as string | undefined
    const amount    = record.amount     as number | undefined

    let authUserId: string | null = null

    if (riderId) {
      const { data } = await supabase
        .from('riders')
        .select('auth_user_id')
        .eq('id', riderId)
        .maybeSingle()
      authUserId = data?.auth_user_id ?? null
    } else if (companyId) {
      const { data } = await supabase
        .from('companies')
        .select('auth_user_id')
        .eq('id', companyId)
        .maybeSingle()
      authUserId = data?.auth_user_id ?? null
    }

    if (!authUserId) return json({ ok: true, reason: 'no auth_user_id found' })

    const { data: tokenRow } = await supabase
      .from('device_tokens')
      .select('token')
      .eq('auth_user_id', authUserId)
      .maybeSingle()

    if (!tokenRow?.token) return json({ ok: true, reason: 'no device token on file' })

    const amountStr = amount ? ` of ₦${Math.round(amount).toLocaleString()}` : ''

    await fetch(notifyUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: authHeader },
      body: JSON.stringify({
        token: tokenRow.token,
        title: '🎉 Bid Accepted!',
        body: `Your bid${amountStr} was accepted. Head to the pickup location now!`,
        data: {
          type: 'bid_accepted',
          delivery_id: record.delivery_id as string,
          bid_id:      record.id          as string,
        },
      }),
    })

    return json({ ok: true })
  } catch (err) {
    return json({ error: (err as Error).message }, 500)
  }
})
