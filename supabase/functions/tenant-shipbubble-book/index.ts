import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { validateApiKey } from '../_shared/auth.ts'
import { cors, json } from '../_shared/cors.ts'

// ── Tenant-authenticated twin of shipbubble-book-shipment. Precheck
// tenants.wallet_balance -> Shipbubble create-shipment -> only on success,
// finalize_book_external_carrier_for_tenant (service-role only, see the
// migration that created it -- this function IS the trust boundary that
// RPC relies on, via validateApiKey below).

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
    const { quote_id } = await req.json() as { quote_id: string }
    if (!quote_id) return json({ error: 'quote_id required' }, 400)

    const { data: quote } = await supabase
      .from('external_carrier_quotes')
      .select('id, delivery_id, tenant_id, courier_id, service_code, total, request_token, expires_at')
      .eq('id', quote_id)
      .maybeSingle()

    if (!quote) return json({ error: 'Quote not found' }, 404)
    if (quote.tenant_id !== auth.tenantId) return json({ error: 'Not authorized for this quote' }, 403)
    if (quote.expires_at && new Date(quote.expires_at) < new Date()) {
      return json({ error: 'This quote has expired — get new rates and try again.' }, 400)
    }

    // "Insufficient tenant balance" means nothing to a tenant's own buyer --
    // it's the merchant's prepaid Eziza balance, not the buyer's wallet.
    // Customer-facing message here instead; the real cause is still visible
    // to the tenant via their own eziza-partners dashboard.
    const { data: tenant } = await supabase.from('tenants').select('wallet_balance').eq('id', auth.tenantId).single()
    if (!tenant || Number(tenant.wallet_balance ?? 0) < Number(quote.total)) {
      return json({ error: 'Instant Courier is temporarily unavailable for this store. Please choose a different delivery option.' }, 400)
    }

    const bookRes = await fetch(`${SHIPBUBBLE_BASE}/shipping/labels`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        request_token: quote.request_token,
        service_code:  quote.service_code,
        courier_id:    quote.courier_id,
      }),
    })
    const bookBody = await bookRes.json()
    if (!bookRes.ok) {
      return json({ error: `Shipbubble booking failed: ${JSON.stringify(bookBody)}` }, 502)
    }

    const shipbubbleOrderId = bookBody.data.order_id as string
    const trackingUrl       = bookBody.data.tracking_url as string | undefined

    const { data: bookingId, error: finalizeErr } = await supabase.rpc('finalize_book_external_carrier_for_tenant', {
      p_quote_id: quote_id,
      p_tenant_id: auth.tenantId,
      p_shipbubble_order_id: shipbubbleOrderId,
      p_tracking_url: trackingUrl ?? null,
    })

    if (finalizeErr) {
      try {
        await fetch(`${SHIPBUBBLE_BASE}/shipping/labels/cancel/${shipbubbleOrderId}`, {
          method: 'POST',
          headers: { 'Authorization': `Bearer ${apiKey}`, 'Accept': 'application/json' },
        })
      } catch (_) { /* best-effort compensation, already returning the real error below */ }
      return json({ error: finalizeErr.message }, 500)
    }

    return json({ booking_id: bookingId, shipbubble_order_id: shipbubbleOrderId, tracking_url: trackingUrl })
  } catch (err) {
    return json({ error: (err as Error).message }, 500)
  }
})
