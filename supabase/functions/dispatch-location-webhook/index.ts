import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { cors, json } from '../_shared/cors.ts'

// Called by Supabase Database Webhook on rider_locations UPDATE.
// Relays the rider's live position to the tenant webhook (e.g. ZeeFashion's
// logistics-gateway) for any of their deliveries this rider is currently
// active on, so the tenant can show a live map without its own credentials
// touching Eziza's rider_locations table directly.

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
)

const WEBHOOK_SECRET = Deno.env.get('WEBHOOK_SIGNING_SECRET') ?? ''

const ACTIVE_STATUSES = ['assigned', 'awaiting_pickup_confirm', 'picked_up']

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

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })

  try {
    const { record } = await req.json()
    // rider_locations.rider_id is the rider's auth.uid() (by design — see
    // 20260704000004_fix_rider_locations_fk.sql), but deliveries.rider_id
    // is riders.id (a different PK) — translate before querying.
    const authUserId = record?.rider_id as string | undefined
    const latitude  = record?.latitude as number | undefined
    const longitude = record?.longitude as number | undefined
    if (!authUserId || latitude == null || longitude == null) return json({ ok: true })

    const { data: riderRow } = await supabase
      .from('riders')
      .select('id')
      .eq('auth_user_id', authUserId)
      .maybeSingle()

    if (!riderRow) return json({ ok: true })

    const { data: activeDeliveries } = await supabase
      .from('deliveries')
      .select('id, tenant_id, external_order_id')
      .eq('rider_id', riderRow.id)
      .in('status', ACTIVE_STATUSES)

    if (!activeDeliveries?.length) return json({ ok: true })

    for (const delivery of activeDeliveries) {
      const { data: tenant } = await supabase
        .from('tenants')
        .select('webhook_url, is_active')
        .eq('id', delivery.tenant_id)
        .single()

      if (!tenant?.webhook_url || !tenant.is_active) continue

      const payload = JSON.stringify({
        event:             'location.updated',
        delivery_id:       delivery.id,
        external_order_id: delivery.external_order_id,
        latitude,
        longitude,
        updated_at: record.updated_at ?? new Date().toISOString(),
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
        delivery_id:     delivery.id,
        tenant_id:       delivery.tenant_id,
        event:           'location.updated',
        payload:         JSON.parse(payload),
        response_status: responseStatus,
        error:           errorMsg,
      })
    }

    return json({ ok: true })
  } catch (err) {
    return json({ error: err.message }, 500)
  }
})
