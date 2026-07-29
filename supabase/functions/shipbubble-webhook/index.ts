import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { json } from '../_shared/cors.ts'

// ── Inbound webhook from Shipbubble on shipment status change ────────────
// Signed with x-ship-signature = HMAC-SHA512(raw body, SECRET_KEY) per
// Shipbubble's docs -- same primitive (HMAC) already used for Eziza's own
// outbound tenant webhooks, just SHA-512 instead of SHA-256.
//
// Exact webhook payload field names aren't confirmed against a real event
// yet (account not approved) -- this defensively checks a couple of
// reasonable candidates and always stores the full raw payload into
// status_history regardless, so nothing is lost even if a field name
// guess is wrong. Revisit once a real webhook has actually been received.

const serviceClient = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
)

const WEBHOOK_SECRET = Deno.env.get('SHIPBUBBLE_WEBHOOK_SECRET') ?? ''

// Shipbubble status -> our booking status. Their own set, confirmed via
// docs: pending/confirmed/picked_up/in_transit/completed/cancelled.
const STATUS_MAP: Record<string, string> = {
  pending:     'pending',
  confirmed:   'confirmed',
  picked_up:   'picked_up',
  in_transit:  'in_transit',
  completed:   'completed',
  cancelled:   'cancelled',
}

async function verifySignature(payload: string, signatureHex: string): Promise<boolean> {
  try {
    const key = await crypto.subtle.importKey(
      'raw',
      new TextEncoder().encode(WEBHOOK_SECRET),
      { name: 'HMAC', hash: 'SHA-512' },
      false,
      ['verify'],
    )
    const sigBytes = new Uint8Array(
      signatureHex.match(/.{2}/g)!.map((b) => parseInt(b, 16)),
    )
    return await crypto.subtle.verify('HMAC', key, sigBytes, new TextEncoder().encode(payload))
  } catch {
    return false
  }
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok')

  const signature = req.headers.get('x-ship-signature')
  const rawBody   = await req.text()

  if (!signature || !WEBHOOK_SECRET) return json({ error: 'Unauthorized' }, 401)
  const valid = await verifySignature(rawBody, signature)
  if (!valid) return json({ error: 'Invalid signature' }, 401)

  try {
    const payload = JSON.parse(rawBody)
    const shipbubbleOrderId = (payload.order_id ?? payload.data?.order_id) as string | undefined
    const rawStatus = (payload.status ?? payload.data?.status ?? payload.event) as string | undefined

    if (!shipbubbleOrderId || !rawStatus) return json({ ok: true, reason: 'no order_id/status in payload' })

    const newStatus = STATUS_MAP[rawStatus]
    if (!newStatus) return json({ ok: true, reason: `unrecognised status '${rawStatus}'` })

    const { data: booking } = await serviceClient
      .from('external_carrier_bookings')
      .select('id, delivery_id, status, status_history')
      .eq('shipbubble_order_id', shipbubbleOrderId)
      .maybeSingle()

    if (!booking) return json({ ok: true, reason: 'no matching booking' })
    if (booking.status === newStatus) return json({ ok: true, reason: 'no status change' })
    // Terminal states don't move backward.
    if (['cancelled', 'completed'].includes(booking.status)) {
      return json({ ok: true, reason: 'booking already in a terminal state' })
    }

    const history = Array.isArray(booking.status_history) ? booking.status_history : []
    history.push({ status: newStatus, at: new Date().toISOString(), raw: payload })

    await serviceClient
      .from('external_carrier_bookings')
      .update({ status: newStatus, status_history: history, updated_at: new Date().toISOString() })
      .eq('id', booking.id)

    // Reflect onto the delivery for the customer-facing UI. 'completed'
    // maps to Eziza's own 'confirmed' (matches how every other fulfillment
    // channel represents "done" in this table); 'cancelled' needs no
    // wallet action here -- a carrier-initiated cancellation (as opposed
    // to the customer calling shipbubble-cancel) has no refund path yet,
    // flagged as a known gap until this is live-tested.
    //
    // 'picked_up' also reflects onto deliveries.status (Eziza's own
    // vocabulary already has this exact value) -- gives both customers and
    // tenants the same granular status visibility already true for
    // internal rider deliveries. This also means tenants get it for free:
    // the existing on_delivery_update_notify trigger fires on any
    // deliveries status change regardless of which function performs the
    // update, and already relays to a tenant's webhook_url via
    // dispatch-webhook -- no new tenant-relay code needed here at all.
    //
    // Deliberately NOT mapped: Shipbubble's own 'confirmed' status (their
    // early lifecycle "order accepted", not "done") never touches
    // deliveries.status='confirmed' here, since that value means "done" in
    // Eziza's vocabulary -- only 'completed' maps to it.
    if (newStatus === 'completed') {
      await serviceClient
        .from('deliveries')
        .update({ status: 'confirmed', confirmed_at: new Date().toISOString() })
        .eq('id', booking.delivery_id)
    } else if (newStatus === 'cancelled') {
      await serviceClient
        .from('deliveries')
        .update({ status: 'cancelled', cancelled_at: new Date().toISOString() })
        .eq('id', booking.delivery_id)
    } else if (newStatus === 'picked_up') {
      await serviceClient
        .from('deliveries')
        .update({ status: 'picked_up' })
        .eq('id', booking.delivery_id)
    }

    return json({ ok: true })
  } catch (err) {
    return json({ error: (err as Error).message }, 500)
  }
})
