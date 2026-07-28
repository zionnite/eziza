import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { cors, json } from '../_shared/cors.ts'

// ── Customer-initiated cancellation of their own external carrier booking.
// Shipbubble cancel-shipment first (it only works for a shipment "processed
// for a future date" per their docs -- if it's already out for pickup this
// will fail and we correctly don't touch the wallet), then refund via
// cancel_external_carrier_booking only on their confirmed success.

const SHIPBUBBLE_BASE = 'https://api.shipbubble.com/v1'

const serviceClient = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
)

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })

  const authHeader = req.headers.get('Authorization')
  if (!authHeader) return json({ error: 'Unauthorized' }, 401)

  const userClient = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: authHeader } } },
  )
  const { data: { user }, error: authErr } = await userClient.auth.getUser()
  if (authErr || !user) return json({ error: 'Unauthorized' }, 401)

  const apiKey = Deno.env.get('SHIPBUBBLE_API_KEY')
  if (!apiKey) return json({ error: 'Shipbubble is not configured yet' }, 503)

  try {
    const { booking_id } = await req.json() as { booking_id: string }
    if (!booking_id) return json({ error: 'booking_id required' }, 400)

    const { data: booking } = await serviceClient
      .from('external_carrier_bookings')
      .select('id, customer_id, shipbubble_order_id, status')
      .eq('id', booking_id)
      .maybeSingle()

    if (!booking) return json({ error: 'Booking not found' }, 404)
    if (booking.customer_id !== user.id) return json({ error: 'Not authorized for this booking' }, 403)
    if (booking.status === 'cancelled' || booking.status === 'completed') {
      return json({ error: `Cannot cancel a booking with status '${booking.status}'` }, 409)
    }

    const cancelRes = await fetch(`${SHIPBUBBLE_BASE}/shipping/labels/cancel/${booking.shipbubble_order_id}`, {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${apiKey}`, 'Accept': 'application/json' },
    })
    const cancelBody = await cancelRes.json()
    if (!cancelRes.ok || cancelBody.status !== 'success') {
      return json({ error: `Shipbubble could not cancel this shipment: ${JSON.stringify(cancelBody)}` }, 409)
    }

    const { error: rpcErr } = await userClient.rpc('cancel_external_carrier_booking', {
      p_booking_id: booking_id,
      p_customer_id: user.id,
    })
    if (rpcErr) throw rpcErr

    return json({ ok: true })
  } catch (err) {
    return json({ error: (err as Error).message }, 500)
  }
})
