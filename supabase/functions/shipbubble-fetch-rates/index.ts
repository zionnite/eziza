import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { cors, json } from '../_shared/cors.ts'
import { getPlatformFeePct, applyCommission } from '../_shared/commission.ts'

// ── Customer requests external-carrier quotes for one of their own open
// deliveries. Mirrors Shipbubble's real flow: address/validate (sender +
// receiver) -> fetch_rates. Quotes are stored so shipbubble-book-shipment
// can reuse the request_token later without re-validating addresses.

const SHIPBUBBLE_BASE = 'https://api.shipbubble.com/v1'

const serviceClient = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
)

// Shipbubble's own validation messages are accurate but not customer-facing
// -- e.g. it uses "please provide a full name" for a single-word name, and a
// generic "couldn't validate the provided address" for one it can't geocode.
// Translated here into something a customer can actually act on, since
// these two are the failure modes actually seen live (2026-08-08, tenant
// side): a profile with no last name, and a placeholder pickup address.
function friendlyAddressError(role: 'sender' | 'receiver', name: string, body: Record<string, unknown>): string {
  const raw = (body?.message ?? (Array.isArray(body?.errors) ? body.errors[0] : undefined) ?? '') as string
  const who = role === 'sender' ? 'Your name' : "The recipient's name"
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
    const body = await req.json()
    const {
      delivery_id,
      category_id,
      package_dimension, // { length, width, height } in cm, from whichever
                          // box the client picked out of
                          // shipbubble-package-options' pass-through response
      unit_weight,        // kg
    } = body as {
      delivery_id: string
      category_id: number
      package_dimension: { length: number; width: number; height: number }
      unit_weight: number
    }

    if (!delivery_id || !category_id || !package_dimension || !unit_weight) {
      return json({ error: 'Required: delivery_id, category_id, package_dimension, unit_weight' }, 400)
    }

    const { data: delivery } = await serviceClient
      .from('deliveries')
      .select('id, customer_id, status, pickup_address, pickup_lat, pickup_lng, pickup_contact_name, pickup_contact_phone, delivery_address, delivery_lat, delivery_lng, delivery_contact_name, delivery_contact_phone, package_description, package_value')
      .eq('id', delivery_id)
      .maybeSingle()

    if (!delivery) return json({ error: 'Delivery not found' }, 404)
    if (delivery.customer_id !== user.id) return json({ error: 'Not authorized for this delivery' }, 403)
    if (delivery.status !== 'open') return json({ error: 'Delivery is not open' }, 409)

    // Sender is always the logged-in customer (email not otherwise
    // collected on the delivery itself). Receiver email isn't collected at
    // all in this schema -- Shipbubble requires the field, so a
    // non-deliverable placeholder is used; this is address *validation*,
    // not an email being sent anywhere.
    //
    // Sender name: delivery.pickup_contact_name is a snapshot taken once at
    // delivery-creation time, never re-synced afterward -- confirmed live
    // 2026-08-10, updating the profile's full_name didn't fix a "needs a
    // full name" error on a retry because this was still reading the old
    // value. Since the sender IS the logged-in customer here (not a
    // separate person, unlike the receiver), prefer their current
    // customers.full_name so a profile fix takes effect immediately without
    // needing a new delivery.
    const { data: customer } = await serviceClient
      .from('customers')
      .select('full_name')
      .eq('id', user.id)
      .maybeSingle()

    const senderCode = await validateAddress(apiKey, 'sender', {
      name:  customer?.full_name || delivery.pickup_contact_name || 'Sender',
      email: user.email ?? `sender+${delivery_id}@eziza.online`,
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
        sender_address_code:    senderCode,
        reciever_address_code:  receiverCode,
        pickup_date:             pickupDate,
        category_id,
        package_items: [{
          name:        delivery.package_description || 'Package',
          description: delivery.package_description || 'Package',
          unit_weight: String(unit_weight),
          unit_amount: String(delivery.package_value ?? 1000),
          quantity:    '1',
        }],
        package_dimension,
      }),
    })
    const ratesBody = await ratesRes.json()
    if (!ratesRes.ok) throw new Error(`fetch_rates failed: ${JSON.stringify(ratesBody)}`)

    const requestToken = ratesBody.data.request_token as string
    const couriers = (ratesBody.data.couriers ?? []) as Array<Record<string, unknown>>

    // Fresh quote set each time -- same delete-then-insert convention
    // already used for OTPs on a resend.
    await serviceClient.from('external_carrier_quotes').delete().eq('delivery_id', delivery_id)

    const feePct = await getPlatformFeePct(serviceClient)
    const rows = couriers.map((c) => {
      const carrierCost = Number(c.total)
      const { total, commission } = applyCommission(carrierCost, feePct)
      return {
        delivery_id,
        customer_id:  user.id,
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

    const { data: inserted, error: insertErr } = await serviceClient
      .from('external_carrier_quotes')
      .insert(rows)
      .select('id, courier_id, courier_name, service_code, total, currency, delivery_eta, pickup_eta, service_type')

    if (insertErr) throw insertErr

    return json({ quotes: inserted })
  } catch (err) {
    return json({ error: (err as Error).message }, 500)
  }
})
