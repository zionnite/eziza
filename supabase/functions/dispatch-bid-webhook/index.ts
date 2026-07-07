import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { cors, json } from '../_shared/cors.ts'

// Called by Supabase Database Webhook on delivery_bids INSERT.
// Relays a placed bid to the tenant's webhook (e.g. ZeeFashion's
// logistics-gateway) so the tenant's own buyer can see it — additive
// alongside notify-bid-placed, which continues to push-notify self-service
// Eziza customers unchanged.

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

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })

  try {
    const { record } = await req.json()
    const deliveryId = record?.delivery_id as string | undefined
    const bidId       = record?.id as string | undefined
    if (!deliveryId || !bidId) return json({ ok: true })

    const { data: delivery } = await supabase
      .from('deliveries')
      .select('id, tenant_id, external_order_id')
      .eq('id', deliveryId)
      .maybeSingle()

    if (!delivery) return json({ ok: true })

    // tenant_id is always set (self-service customers use the sentinel
    // "Eziza Direct" tenant, whose webhook_url is null) — so the real
    // discriminator is webhook_url, matching dispatch-webhook's convention.
    const { data: tenant } = await supabase
      .from('tenants')
      .select('webhook_url, is_active')
      .eq('id', delivery.tenant_id)
      .single()

    if (!tenant?.webhook_url || !tenant.is_active) return json({ ok: true })

    const payload = JSON.stringify({
      event:             'bid.placed',
      delivery_id:       deliveryId,
      external_order_id: delivery.external_order_id,
      bid: {
        id:          bidId,
        bidder_type: record.rider_id ? 'rider' : 'company',
        rider_id:    record.rider_id   ?? null,
        company_id:  record.company_id ?? null,
        amount:      record.amount,
        status:      record.status ?? 'pending',
      },
      timestamp: new Date().toISOString(),
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
          'X-Eziza-Event':     'bid.placed',
        },
        body: payload,
      })
      responseStatus = res.status
    } catch (fetchErr) {
      errorMsg = fetchErr.message
    }

    await supabase.from('webhook_dispatch_log').insert({
      delivery_id:     deliveryId,
      tenant_id:       delivery.tenant_id,
      event:           'bid.placed',
      payload:         JSON.parse(payload),
      response_status: responseStatus,
      error:           errorMsg,
    })

    return json({ ok: true, response_status: responseStatus })
  } catch (err) {
    return json({ error: err.message }, 500)
  }
})
