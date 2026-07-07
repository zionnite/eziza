import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { cors, json } from '../_shared/cors.ts'

// Called by Supabase Database Webhook on deliveries UPDATE.
// Signs the payload with HMAC-SHA256 so the receiver can verify it's genuine.

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
)

const WEBHOOK_SECRET = Deno.env.get('WEBHOOK_SIGNING_SECRET') ?? ''

async function sign(payload: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(WEBHOOK_SECRET),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  )
  const sig = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(payload))
  return Array.from(new Uint8Array(sig))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('')
}

// Events we dispatch to tenants
const DISPATCH_EVENTS: Record<string, string> = {
  assigned:                'delivery.assigned',
  awaiting_pickup_confirm: 'delivery.awaiting_pickup',
  picked_up:               'delivery.picked_up',
  delivered:               'delivery.delivered',
  confirmed:               'delivery.confirmed',
  cancelled:               'delivery.cancelled',
}

// ── FCM helpers ───────────────────────────────────────────────

const notifyUrl  = `${Deno.env.get('SUPABASE_URL')}/functions/v1/send-notification`
const authHeader = `Bearer ${Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')}`

async function sendPush(
  token: string,
  title: string,
  body:  string,
  data:  Record<string, string>,
): Promise<void> {
  await fetch(notifyUrl, {
    method:  'POST',
    headers: { 'Content-Type': 'application/json', Authorization: authHeader },
    body:    JSON.stringify({ token, title, body, data }),
  })
}

async function notifyUser(
  authUserId: string,
  title:      string,
  body:       string,
  data:       Record<string, string>,
): Promise<void> {
  const { data: row } = await supabase
    .from('device_tokens')
    .select('token')
    .eq('auth_user_id', authUserId)
    .maybeSingle()

  if (!row?.token) return
  await sendPush(row.token, title, body, data)
}

// ── Main handler ──────────────────────────────────────────────

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })

  try {
    // Supabase DB webhook sends { type, table, schema, record, old_record }
    const { record, old_record } = await req.json()

    const newStatus = record?.status as string | undefined
    const oldStatus = old_record?.status as string | undefined

    // Only dispatch when status actually changed to a dispatch-worthy event
    if (!newStatus || newStatus === oldStatus) return json({ ok: true })
    const event = DISPATCH_EVENTS[newStatus]
    if (!event) return json({ ok: true })

    const tenantId = record.tenant_id as string

    // Get tenant webhook URL
    const { data: tenant } = await supabase
      .from('tenants')
      .select('webhook_url, is_active')
      .eq('id', tenantId)
      .single()

    if (!tenant?.webhook_url || !tenant.is_active) return json({ ok: true })

    const payload = JSON.stringify({
      event,
      delivery_id:       record.id,
      external_order_id: record.external_order_id,
      external_ref:      record.external_ref,
      status:            newStatus,
      rider_id:          record.rider_id,
      agreed_price:      record.agreed_price,
      timestamp:         new Date().toISOString(),
    })

    const signature = await sign(payload)

    let responseStatus: number | null = null
    let errorMsg: string | null       = null

    try {
      const res = await fetch(tenant.webhook_url, {
        method:  'POST',
        headers: {
          'Content-Type':       'application/json',
          'X-Eziza-Signature':  signature,
          'X-Eziza-Event':      event,
        },
        body: payload,
      })
      responseStatus = res.status
    } catch (fetchErr) {
      errorMsg = fetchErr.message
    }

    // Log dispatch attempt
    await supabase.from('webhook_dispatch_log').insert({
      delivery_id:     record.id,
      tenant_id:       tenantId,
      event,
      payload:         JSON.parse(payload),
      response_status: responseStatus,
      error:           errorMsg,
    })

    // ── Push notifications ────────────────────────────────────
    const deliveryId   = record.id as string
    const customerId   = record.customer_id as string | undefined

    if (newStatus === 'assigned') {
      // Winning rider/company is already notified by the delivery_bids
      // UPDATE→accepted trigger (notify-bid-accepted), which correctly
      // covers both bidder types via the current device_tokens table.
      // Notify the customer
      if (customerId) {
        await notifyUser(
          customerId,
          '🚴 Rider Assigned',
          'A rider is on the way to your pickup location.',
          { type: 'delivery_update', delivery_id: deliveryId, status: 'assigned' },
        ).catch(() => {})
      }
    } else if (newStatus === 'picked_up' && customerId) {
      await notifyUser(
        customerId,
        '📦 Package Picked Up',
        'Your package has been picked up and is on the way!',
        { type: 'delivery_update', delivery_id: deliveryId, status: 'picked_up' },
      ).catch(() => {})
    } else if (newStatus === 'delivered' && customerId) {
      await notifyUser(
        customerId,
        '🎉 Package Delivered',
        'Your package has arrived! Please confirm receipt.',
        { type: 'delivery_update', delivery_id: deliveryId, status: 'delivered' },
      ).catch(() => {})
    }

    return json({ ok: true, event, response_status: responseStatus })
  } catch (err) {
    return json({ error: err.message }, 500)
  }
})
