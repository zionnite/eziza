import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { json } from '../_shared/cors.ts'

// Called by DB trigger on_delivery_insert_notify_riders on every deliveries INSERT.
//
// Rider matching (either condition qualifies):
//   1. State match  — rider.coverage_states contains delivery.pickup_state
//   2. Radius match — rider has a GPS location within 50 km of the pickup
//
// Companies are notified if their state matches pickup_state, or if they have
// no state set (notify all approved companies as a fallback).

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
)

const MAX_RADIUS_KM = 50

function distKm(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const R    = 6371
  const dLat = (lat2 - lat1) * Math.PI / 180
  const dLng = (lng2 - lng1) * Math.PI / 180
  const a    =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
    Math.sin(dLng / 2) ** 2
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok')

  try {
    const { record } = await req.json()
    if (record?.status !== 'open') return json({ ok: true, reason: 'not open' })
    // Sandbox deliveries never appear on the real job board (RLS filters
    // them out) -- pushing "new job near you" for one anyway would be a
    // real, confusing regression for actual riders/companies.
    if (record?.is_sandbox) return json({ ok: true, reason: 'sandbox' })

    const pickupLat   = typeof record.pickup_lat   === 'number' ? record.pickup_lat   as number : null
    const pickupLng   = typeof record.pickup_lng   === 'number' ? record.pickup_lng   as number : null
    const pickupState = (record.pickup_state as string | null)?.trim().toLowerCase() ?? null
    const pickup      = (record.pickup_address as string | null) ?? 'Unknown location'
    const short       = pickup.length > 60 ? pickup.slice(0, 57) + '…' : pickup
    const deliveryId  = record.id as string

    const notifyUrl  = `${Deno.env.get('SUPABASE_URL')}/functions/v1/send-notification`
    const authHeader = `Bearer ${Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')}`

    // send-notification returns 200/{ok:true} both when it genuinely sent a
    // push AND when it silently no-op'd on a missing token ({reason:'no_token'})
    // -- checking res.ok alone (as this used to) counts the second case as a
    // real send, which is exactly how "riders:2" showed up in logs for
    // deliveries where neither matched rider actually had a device token.
    const push = async (userId: string, title: string, body: string, data: Record<string, string>) => {
      const res = await fetch(notifyUrl, {
        method:  'POST',
        headers: { 'Content-Type': 'application/json', Authorization: authHeader },
        body:    JSON.stringify({ user_id: userId, title, body, data }),
      })
      const result = await res.json().catch(() => null)
      return { delivered: res.ok && !result?.reason, result }
    }

    // ── 1. Riders ─────────────────────────────────────────────────────────────
    const { data: riders } = await supabase
      .from('riders')
      .select('auth_user_id, coverage_states')
      .eq('is_available', true)
      .eq('status', 'approved')
      .not('auth_user_id', 'is', null)

    // Fetch all rider locations in one query (rider_id = auth.uid())
    const { data: locations } = await supabase
      .from('rider_locations')
      .select('rider_id, latitude, longitude')

    const locByUid = new Map(
      (locations ?? []).map((l) => [l.rider_id as string, l])
    )

    let ridersSent = 0
    let ridersMatchedNoToken = 0
    const countRider = (r: { delivered: boolean; result: { reason?: string } | null }) => {
      if (r.delivered) ridersSent++
      else if (r.result?.reason === 'no_token') ridersMatchedNoToken++
    }
    const riderJobs = (riders ?? []).map((r) => {
      const coverage: string[] = r.coverage_states ?? []

      // ── Condition 1: state match ───────────────────────────────────────────
      if (pickupState && coverage.some((s) => s.trim().toLowerCase() === pickupState)) {
        return push(
          r.auth_user_id,
          '📦 New Job Available',
          `Pickup: ${short}`,
          { type: 'new_job', delivery_id: deliveryId },
        ).then(countRider)
      }

      // ── Condition 2: GPS radius match ──────────────────────────────────────
      const loc = locByUid.get(r.auth_user_id)
      if (!loc) return Promise.resolve() // no location — can't verify proximity
      if (pickupLat === null || pickupLng === null) return Promise.resolve() // no pickup coords
      if (distKm(loc.latitude, loc.longitude, pickupLat, pickupLng) > MAX_RADIUS_KM) {
        return Promise.resolve()
      }

      return push(
        r.auth_user_id,
        '📦 New Job Available',
        `Pickup: ${short}`,
        { type: 'new_job', delivery_id: deliveryId },
      ).then(countRider)
    })

    // ── 2. Companies ──────────────────────────────────────────────────────────
    // Match by company.state if set; notify all approved companies when no
    // state is on file yet (companies are still being onboarded).
    const { data: companies } = await supabase
      .from('companies')
      .select('auth_user_id, state')
      .eq('is_approved', true)
      .not('auth_user_id', 'is', null)

    let companiesSent = 0
    let companiesMatchedNoToken = 0
    const companyJobs = (companies ?? []).map((c) => {
      const companyState = (c.state as string | null)?.trim().toLowerCase()

      // If company has a state set, only notify if it matches pickup state
      if (companyState && pickupState && companyState !== pickupState) {
        return Promise.resolve()
      }

      return push(
        c.auth_user_id,
        '📦 New Delivery Request',
        `Pickup: ${short}`,
        { type: 'new_job', delivery_id: deliveryId },
      ).then((r) => {
        if (r.delivered) companiesSent++
        else if (r.result?.reason === 'no_token') companiesMatchedNoToken++
      })
    })

    await Promise.allSettled([...riderJobs, ...companyJobs])

    return json({
      ok: true,
      riders: ridersSent,
      companies: companiesSent,
      riders_matched_no_token: ridersMatchedNoToken,
      companies_matched_no_token: companiesMatchedNoToken,
    })
  } catch (err) {
    return json({ error: (err as Error).message }, 500)
  }
})
