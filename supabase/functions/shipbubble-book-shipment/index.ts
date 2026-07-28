import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { cors, json } from '../_shared/cors.ts'

// ── Precheck balance -> Shipbubble create-shipment -> only on Shipbubble
// success does finalize_book_external_carrier commit the wallet debit +
// booking row. Mirrors the precheck/finalize pattern already proven for
// ZeeFashion's Eziza-bid-accept flow (accept on their side first, commit
// payment only after, compensate on failure).

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
    const { quote_id } = await req.json() as { quote_id: string }
    if (!quote_id) return json({ error: 'quote_id required' }, 400)

    const { data: quote } = await serviceClient
      .from('external_carrier_quotes')
      .select('id, delivery_id, customer_id, courier_id, service_code, total, expires_at, request_token')
      .eq('id', quote_id)
      .maybeSingle()

    if (!quote) return json({ error: 'Quote not found' }, 404)
    if (quote.customer_id !== user.id) return json({ error: 'Not authorized for this quote' }, 403)
    if (quote.expires_at && new Date(quote.expires_at) < new Date()) {
      return json({ error: 'This quote has expired — get new rates and try again.' }, 400)
    }

    // Fail fast on an obviously-doomed booking before spending a real
    // Shipbubble API call — finalize_book_external_carrier re-checks this
    // itself right before actually debiting, which is the check that
    // actually matters against a race.
    const { data: customer } = await serviceClient
      .from('customers')
      .select('wallet_balance')
      .eq('id', user.id)
      .maybeSingle()
    if (!customer || Number(customer.wallet_balance ?? 0) < Number(quote.total)) {
      return json({ error: 'Insufficient wallet balance' }, 400)
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

    const { data: bookingId, error: finalizeErr } = await userClient.rpc('finalize_book_external_carrier', {
      p_quote_id: quote_id,
      p_customer_id: user.id,
      p_shipbubble_order_id: shipbubbleOrderId,
      p_tracking_url: trackingUrl ?? null,
    })

    if (finalizeErr) {
      // Shipbubble already created a real shipment but our own commit
      // failed (e.g. a balance race) -- compensate by cancelling it on
      // their side rather than leaving a real, unpaid shipment dangling.
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
