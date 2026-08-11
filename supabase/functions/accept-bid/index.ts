import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { validateApiKey } from '../_shared/auth.ts'
import { cors, json } from '../_shared/cors.ts'

// Tenant (e.g. ZeeFashion) accepts a bid on behalf of a buyer who has no
// Eziza account/session. Mirrors customer_delivery_detail_page.dart's
// _acceptBid(), scoped by tenant_id instead of a logged-in customer.
//
// Now debits the tenant's own prepaid Eziza wallet the bid amount,
// atomically with accepting it (accept_bid_for_tenant RPC) -- previously
// this only changed status, with no payment step at all, so an Eziza
// rider/company got credited in full at delivery-confirm time with
// nothing ever collected from the tenant. Same prepaid-wallet mechanism
// External Carrier bookings already use (finalize_book_external_carrier_
// for_tenant), closing the "uncollected-commission gap" documented in
// 20260730000000_external_carriers_for_tenants.sql -- confirmed live
// 2026-08-10/11 via a full money-flow trace.

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

    const { data, error } = await supabase
      .rpc('accept_bid_for_tenant', {
        p_delivery_id: delivery_id,
        p_bid_id:      bid_id,
        p_tenant_id:   auth.tenantId,
      })
      .single()

    if (error) {
      // "Insufficient tenant balance" means nothing to a tenant's own buyer
      // -- it's the merchant's prepaid Eziza balance, not the buyer's
      // wallet. Same customer-facing message tenant-shipbubble-book already
      // uses for the identical situation; the real cause is still visible
      // to the tenant via their own eziza-partners dashboard.
      if (error.message.includes('Insufficient tenant balance')) {
        return json({ error: 'This delivery option is temporarily unavailable. Please choose a different one.' }, 400)
      }
      return json({ error: error.message }, 400)
    }

    const result = data as { rider_id: string | null; agreed_price: number }
    return json({
      delivery_id, bid_id, status: 'assigned',
      rider_id: result.rider_id, agreed_price: result.agreed_price,
    })
  } catch (err) {
    return json({ error: err.message }, 500)
  }
})
