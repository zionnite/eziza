import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { validateApiKey } from '../_shared/auth.ts'
import { cors, json } from '../_shared/cors.ts'

// ── Tenant-authenticated twin of shipbubble-cancel.

const SHIPBUBBLE_BASE = 'https://api.shipbubble.com/v1'

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
)

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })

  const auth = await validateApiKey(req)
  if (!auth) return json({ error: 'Unauthorized' }, 401)

  const apiKey = Deno.env.get('SHIPBUBBLE_API_KEY')
  if (!apiKey) return json({ error: 'Shipbubble is not configured yet' }, 503)

  try {
    const { booking_id } = await req.json() as { booking_id: string }
    if (!booking_id) return json({ error: 'booking_id required' }, 400)

    const { data: booking } = await supabase
      .from('external_carrier_bookings')
      .select('id, tenant_id, shipbubble_order_id, status')
      .eq('id', booking_id)
      .maybeSingle()

    if (!booking) return json({ error: 'Booking not found' }, 404)
    if (booking.tenant_id !== auth.tenantId) return json({ error: 'Not authorized for this booking' }, 403)
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

    const { error: rpcErr } = await supabase.rpc('cancel_external_carrier_booking_for_tenant', {
      p_booking_id: booking_id,
      p_tenant_id: auth.tenantId,
    })
    if (rpcErr) throw rpcErr

    return json({ ok: true })
  } catch (err) {
    return json({ error: (err as Error).message }, 500)
  }
})
