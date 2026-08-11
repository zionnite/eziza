import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { validateApiKey } from '../_shared/auth.ts'
import { cors, json } from '../_shared/cors.ts'
import { getPlatformFeePct, applyCommission } from '../_shared/commission.ts'

// ── Tenant-authenticated twin of shipbubble-fetch-rates. Package details
// (category/weight/dimension) are read off the delivery row itself, set
// optionally at create-delivery time -- there's no live tenant session to
// interactively prompt the way Eziza's own customer app can.

const SHIPBUBBLE_BASE = 'https://api.shipbubble.com/v1'

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
)

// Shipbubble's own validation messages are accurate but not customer-facing
// -- e.g. it uses "please provide a full name" for a single-word name, and a
// generic "couldn't validate the provided address" for one it can't geocode.
// Translated here into something a merchant/customer can actually act on,
// since these two are the failure modes actually seen live (2026-08-08):
// a customer profile with no last name, and a placeholder pickup address.
function friendlyAddressError(role: 'sender' | 'receiver', name: string, body: Record<string, unknown>): string {
  const raw = (body?.message ?? (Array.isArray(body?.errors) ? body.errors[0] : undefined) ?? '') as string
  const who = role === 'sender' ? "The merchant's pickup contact name" : "The recipient's name"
  if (/full name/i.test(raw)) {
    return `${who} ("${name}") needs a full first and last name -- please update it and try again.`
  }
  if (/couldn't validate|clear and accurate address/i.test(raw)) {
    const which = role === 'sender' ? 'pickup' : 'delivery'
    return `The ${which} address on file couldn't be matched to a real location. Please make sure it includes a full street, city, and state.`
  }
  return raw || `Could not validate the ${role === 'sender' ? 'pickup' : 'delivery'} address.`
}

async function validateAddress(
  apiKey: string,
  role: 'sender' | 'receiver',
  args: { name: string; email: string; phone: string; address: string; lat?: number | null; lng?: number | null },
): Promise<number> {
  const res = await fetch(`${SHIPBUBBLE_BASE}/shipping/address/validate`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'Authorization': `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      name: args.name,
      email: args.email,
      phone: args.phone,
      address: args.address,
      ...(args.lat != null ? { latitude: args.lat } : {}),
      ...(args.lng != null ? { longitude: args.lng } : {}),
    }),
  })
  const body = await res.json()
  if (!res.ok) throw new Error(friendlyAddressError(role, args.name, body))
  return body.data.address_code
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })

  const auth = await validateApiKey(req)
  if (!auth) return json({ error: 'Unauthorized' }, 401)

  const apiKey = Deno.env.get('SHIPBUBBLE_API_KEY')
  if (!apiKey) return json({ error: 'Shipbubble is not configured yet' }, 503)

  try {
    const { delivery_id } = await req.json() as { delivery_id: string }
    if (!delivery_id) return json({ error: 'delivery_id required' }, 400)

    const { data: delivery } = await supabase
      .from('deliveries')
      .select('id, tenant_id, status, pickup_address, pickup_lat, pickup_lng, pickup_contact_name, pickup_contact_phone, delivery_address, delivery_lat, delivery_lng, delivery_contact_name, delivery_contact_phone, package_description, package_value, package_category_id, package_weight_kg, package_dimension')
      .eq('id', delivery_id)
      .maybeSingle()

    if (!delivery) return json({ error: 'Delivery not found' }, 404)
    if (delivery.tenant_id !== auth.tenantId) return json({ error: 'Not authorized for this delivery' }, 403)
    if (delivery.status !== 'open') return json({ error: 'Delivery is not open' }, 409)

    // The full message (field names, "call create-delivery") is meant for
    // ZeeFashion's own logs/devs, not a buyer -- it was reaching customers
    // verbatim as "Could Not Load Quotes" on track_order.dart, confirmed
    // live 2026-08-11. ZeeFashion now hides the "Choose a Delivery Partner"
    // option outright when it knows package details are missing
    // (has_package_details), so this is now defense-in-depth for any
    // delivery created before that fix, or a race between the two.
    if (!delivery.package_category_id || !delivery.package_weight_kg || !delivery.package_dimension) {
      return json({
        error: 'Delivery-partner options aren’t available for this order.',
      }, 400)
    }

    const { data: tenant } = await supabase.from('tenants').select('email, pickup_only_carriers').eq('id', auth.tenantId).single()

    const senderCode = await validateAddress(apiKey, 'sender', {
      name:  delivery.pickup_contact_name || 'Sender',
      email: tenant?.email ?? `sender+${delivery_id}@eziza.online`,
      phone: delivery.pickup_contact_phone || '',
      address: delivery.pickup_address,
      lat: delivery.pickup_lat, lng: delivery.pickup_lng,
    })
    const receiverCode = await validateAddress(apiKey, 'receiver', {
      name:  delivery.delivery_contact_name || 'Receiver',
      email: `receiver+${delivery_id}@eziza.online`,
      phone: delivery.delivery_contact_phone || '',
      address: delivery.delivery_address,
      lat: delivery.delivery_lat, lng: delivery.delivery_lng,
    })

    const pickupDate = new Date().toISOString().slice(0, 10)

    const ratesRes = await fetch(`${SHIPBUBBLE_BASE}/shipping/fetch_rates`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        sender_address_code:   senderCode,
        reciever_address_code: receiverCode,
        pickup_date:            pickupDate,
        category_id:            delivery.package_category_id,
        package_items: [{
          name:        delivery.package_description || 'Package',
          description: delivery.package_description || 'Package',
          unit_weight: String(delivery.package_weight_kg),
          unit_amount: String(delivery.package_value ?? 1000),
          quantity:    '1',
        }],
        package_dimension: delivery.package_dimension,
      }),
    })
    const ratesBody = await ratesRes.json()
    if (!ratesRes.ok) throw new Error(`fetch_rates failed: ${JSON.stringify(ratesBody)}`)

    const requestToken = ratesBody.data.request_token as string
    let couriers = (ratesBody.data.couriers ?? []) as Array<Record<string, unknown>>

    // Some tenants (ZeeFashion, confirmed 2026-08-09) never want a "dropoff"
    // courier offered -- that would mean the merchant has to personally
    // take the package to a station, which isn't how they operate. Only
    // "pickup" couriers (rider comes to the merchant's own location) survive
    // for those tenants; other tenants see every option Shipbubble returns.
    if (tenant?.pickup_only_carriers) {
      couriers = couriers.filter((c) => c.service_type === 'pickup')
    }

    await supabase.from('external_carrier_quotes').delete().eq('delivery_id', delivery_id)

    const feePct = await getPlatformFeePct(supabase)
    const rows = couriers.map((c) => {
      const carrierCost = Number(c.total)
      const { total, commission } = applyCommission(carrierCost, feePct)
      return {
        delivery_id,
        tenant_id:    auth.tenantId,
        courier_id:   String(c.courier_id),
        courier_name: c.courier_name,
        service_code: c.service_code,
        request_token: requestToken,
        total,
        carrier_cost: carrierCost,
        commission_amount: commission,
        currency:     c.currency,
        delivery_eta: c.delivery_eta,
        pickup_eta:   c.pickup_eta,
        service_type: c.service_type,
        raw_response: c,
        expires_at:   new Date(Date.now() + 20 * 60 * 1000).toISOString(),
      }
    })

    const { data: inserted, error: insertErr } = await supabase
      .from('external_carrier_quotes')
      .insert(rows)
      .select('id, courier_id, courier_name, service_code, total, currency, delivery_eta, pickup_eta, service_type')

    if (insertErr) throw insertErr

    return json({ quotes: inserted })
  } catch (err) {
    return json({ error: (err as Error).message }, 500)
  }
})
