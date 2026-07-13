import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { cors, json } from '../_shared/cors.ts'

// Ticked periodically by pg_cron (see migration 20260714020000). Plays the
// rider's role for sandbox deliveries only, so a partner's own integration
// code can exercise the real accept-bid/confirm-pickup/confirm-receipt
// endpoints against something that actually progresses -- without a real
// human rider anywhere. Everything the *tenant* would normally do
// (accept-bid, confirm-pickup, confirm-receipt) is left to them; this only
// simulates what a rider does (bid, arrive at pickup, mark delivered).

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
)

const WEBHOOK_SECRET = Deno.env.get('WEBHOOK_SIGNING_SECRET') ?? ''

const BID_DELAY_MS            = 10_000  // open -> first bid appears
const ARRIVAL_DELAY_MS        = 15_000  // assigned -> awaiting_pickup_confirm
const DELIVERED_DELAY_MS      = 20_000  // picked_up -> delivered

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

// rider_locations has no FK to auth.users, and dispatch-location-webhook's
// own rider lookup expects a real auth_user_id (sandbox riders have none) --
// rather than bend shared infra to fit a fake rider, dispatch this one event
// type directly here, same payload shape and signing as the real thing.
async function simulateLocationPing(
  deliveryId: string,
  tenantId: string,
  externalOrderId: string | null,
  lat: number,
  lng: number,
) {
  const { data: tenant } = await supabase
    .from('tenants')
    .select('webhook_url, is_active')
    .eq('id', tenantId)
    .single()
  if (!tenant?.webhook_url || !tenant.is_active) return

  const payload = JSON.stringify({
    event:             'location.updated',
    delivery_id:       deliveryId,
    external_order_id: externalOrderId,
    latitude:          lat,
    longitude:         lng,
    updated_at:        new Date().toISOString(),
  })
  const signature = await sign(payload)

  let responseStatus: number | null = null
  let errorMsg: string | null       = null
  try {
    const res = await fetch(tenant.webhook_url, {
      method:  'POST',
      headers: {
        'Content-Type':      'application/json',
        'X-Eziza-Signature': signature,
        'X-Eziza-Event':     'location.updated',
      },
      body: payload,
    })
    responseStatus = res.status
  } catch (fetchErr) {
    errorMsg = fetchErr.message
  }

  await supabase.from('webhook_dispatch_log').insert({
    delivery_id:     deliveryId,
    tenant_id:       tenantId,
    event:           'location.updated',
    payload:         JSON.parse(payload),
    response_status: responseStatus,
    error:           errorMsg,
  })
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })

  try {
    const { data: sandboxRiders } = await supabase
      .from('riders')
      .select('id')
      .eq('is_sandbox', true)
    const riderIds = (sandboxRiders ?? []).map((r) => r.id)
    if (riderIds.length === 0) return json({ ok: true, note: 'No sandbox riders configured' })

    let bidsCreated = 0
    let advancedToAwaitingPickup = 0
    let advancedToDelivered = 0

    // 1. open -> generate a bid, once, after a short grace period
    const { data: openDeliveries } = await supabase
      .from('deliveries')
      .select('id, package_value')
      .eq('is_sandbox', true)
      .eq('status', 'open')
      .lt('created_at', new Date(Date.now() - BID_DELAY_MS).toISOString())

    for (const d of openDeliveries ?? []) {
      const { count } = await supabase
        .from('delivery_bids')
        .select('id', { count: 'exact', head: true })
        .eq('delivery_id', d.id)
      if (count) continue

      const riderId = riderIds[Math.floor(Math.random() * riderIds.length)]
      const base = Number(d.package_value) || 3000
      const amount = Math.round(base * (0.4 + Math.random() * 0.3)) || 1500

      const { error } = await supabase
        .from('delivery_bids')
        .insert({ delivery_id: d.id, rider_id: riderId, amount, status: 'pending' })
      if (!error) bidsCreated++
    }

    // 2. assigned -> awaiting_pickup_confirm (rider "arrives" at pickup)
    const { data: assignedDeliveries } = await supabase
      .from('deliveries')
      .select('id, tenant_id, external_order_id, pickup_lat, pickup_lng')
      .eq('is_sandbox', true)
      .eq('status', 'assigned')
      .lt('assigned_at', new Date(Date.now() - ARRIVAL_DELAY_MS).toISOString())

    for (const d of assignedDeliveries ?? []) {
      const { error } = await supabase
        .from('deliveries')
        .update({ status: 'awaiting_pickup_confirm' })
        .eq('id', d.id)
      if (error) continue
      advancedToAwaitingPickup++
      if (d.pickup_lat != null && d.pickup_lng != null) {
        await simulateLocationPing(d.id, d.tenant_id, d.external_order_id, Number(d.pickup_lat), Number(d.pickup_lng))
      }
    }

    // 3. picked_up -> delivered (rider marks delivered)
    const { data: pickedUpDeliveries } = await supabase
      .from('deliveries')
      .select('id, tenant_id, external_order_id, delivery_lat, delivery_lng')
      .eq('is_sandbox', true)
      .eq('status', 'picked_up')
      .lt('picked_up_at', new Date(Date.now() - DELIVERED_DELAY_MS).toISOString())

    for (const d of pickedUpDeliveries ?? []) {
      const { error } = await supabase
        .from('deliveries')
        .update({ status: 'delivered', delivered_at: new Date().toISOString() })
        .eq('id', d.id)
      if (error) continue
      advancedToDelivered++
      if (d.delivery_lat != null && d.delivery_lng != null) {
        await simulateLocationPing(d.id, d.tenant_id, d.external_order_id, Number(d.delivery_lat), Number(d.delivery_lng))
      }
    }

    return json({ ok: true, bidsCreated, advancedToAwaitingPickup, advancedToDelivered })
  } catch (err) {
    return json({ error: err.message }, 500)
  }
})
