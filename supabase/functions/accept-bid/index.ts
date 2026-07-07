import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { validateApiKey } from '../_shared/auth.ts'
import { cors, json } from '../_shared/cors.ts'

// Tenant (e.g. ZeeFashion) accepts a bid on behalf of a buyer who has no
// Eziza account/session. Mirrors customer_delivery_detail_page.dart's
// _acceptBid(), scoped by tenant_id instead of a logged-in customer.

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
)

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })

  const auth = await validateApiKey(req)
  if (!auth) return json({ error: 'Unauthorized' }, 401)

  try {
    const { delivery_id, bid_id } = await req.json()
    if (!delivery_id || !bid_id) {
      return json({ error: 'Required: delivery_id, bid_id' }, 400)
    }

    const { data: delivery } = await supabase
      .from('deliveries')
      .select('id, status, tenant_id')
      .eq('id', delivery_id)
      .eq('tenant_id', auth.tenantId)
      .single()

    if (!delivery) return json({ error: 'Delivery not found' }, 404)
    if (delivery.status !== 'open') {
      return json({ error: `Cannot accept a bid on a delivery with status '${delivery.status}'` }, 409)
    }

    const { data: bid } = await supabase
      .from('delivery_bids')
      .select('id, delivery_id, rider_id, company_id, amount, status')
      .eq('id', bid_id)
      .eq('delivery_id', delivery_id)
      .eq('status', 'pending')
      .single()

    if (!bid) return json({ error: 'Bid not found or already processed' }, 404)

    const { error: acceptErr } = await supabase
      .from('delivery_bids').update({ status: 'accepted' }).eq('id', bid_id)
    if (acceptErr) throw acceptErr

    await supabase
      .from('delivery_bids').update({ status: 'rejected' })
      .eq('delivery_id', delivery_id).neq('id', bid_id).eq('status', 'pending')

    const { error: assignErr } = await supabase
      .from('deliveries')
      .update({
        status:       'assigned',
        rider_id:     bid.rider_id ?? null,
        agreed_price: bid.amount,
        assigned_at:  new Date().toISOString(),
      })
      .eq('id', delivery_id)
    if (assignErr) throw assignErr

    return json({
      delivery_id, bid_id, status: 'assigned',
      rider_id: bid.rider_id ?? null, agreed_price: bid.amount,
    })
  } catch (err) {
    return json({ error: err.message }, 500)
  }
})
