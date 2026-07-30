import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { json } from '../_shared/cors.ts'

// ── Supabase clients ──────────────────────────────────────────────────────────

const serviceClient = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
)

// The delivery's handoff code is generated once, at creation, by the
// deliveries_set_handoff_code trigger -- never here, and never over SMS.
// This function only ever checks a rider's guess against it and reports
// pass/fail; the code itself is never included in any response.

const MAX_ATTEMPTS   = 3
const LOCKOUT_MS     = 2 * 60 * 1000 // 2 minutes

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok')

  // Authenticate caller as a logged-in rider
  const authHeader = req.headers.get('Authorization')
  if (!authHeader) return json({ error: 'Unauthorized' }, 401)

  const userClient = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: authHeader } } },
  )
  const { data: { user }, error: authErr } = await userClient.auth.getUser()
  if (authErr || !user) return json({ error: 'Unauthorized' }, 401)

  try {
    const body = await req.json()
    const { delivery_id, otp } = body as { delivery_id: string; otp?: string }

    if (!delivery_id) return json({ error: 'delivery_id required' }, 400)
    if (!otp?.trim())  return json({ error: 'otp required' }, 400)

    // Fetch delivery + verify the calling user is the assigned rider
    const { data: delivery } = await serviceClient
      .from('deliveries')
      .select('id, status, rider_id')
      .eq('id', delivery_id)
      .maybeSingle()

    if (!delivery) return json({ error: 'Delivery not found' }, 404)

    const { data: rider } = await serviceClient
      .from('riders')
      .select('id')
      .eq('auth_user_id', user.id)
      .maybeSingle()

    if (!rider || delivery.rider_id !== rider.id) {
      return json({ error: 'Not authorised for this delivery' }, 403)
    }

    const { data: codeRow } = await serviceClient
      .from('delivery_otps')
      .select('id, code, attempts, verified_at, locked_until')
      .eq('delivery_id', delivery_id)
      .maybeSingle()

    if (!codeRow) return json({ error: 'No delivery code found for this delivery.' }, 400)
    if (codeRow.verified_at) return json({ error: 'This delivery is already confirmed.' }, 400)

    if (codeRow.locked_until && new Date(codeRow.locked_until) > new Date()) {
      const waitSecs = Math.ceil((new Date(codeRow.locked_until).getTime() - Date.now()) / 1000)
      return json({ error: `Too many incorrect attempts. Try again in ${waitSecs}s.` }, 400)
    }

    if (otp.trim() !== codeRow.code) {
      const attempts = codeRow.attempts + 1
      const lockingNow = attempts >= MAX_ATTEMPTS
      await serviceClient
        .from('delivery_otps')
        .update({
          attempts: lockingNow ? 0 : attempts,
          locked_until: lockingNow
            ? new Date(Date.now() + LOCKOUT_MS).toISOString()
            : null,
        })
        .eq('id', codeRow.id)

      if (lockingNow) {
        return json({ error: `Too many incorrect attempts. Try again in ${LOCKOUT_MS / 1000}s.` }, 400)
      }
      const remaining = MAX_ATTEMPTS - attempts
      return json(
        { error: `Incorrect code. ${remaining} attempt${remaining === 1 ? '' : 's'} left.` },
        400,
      )
    }

    // Correct — mark verified, confirm delivery
    await serviceClient
      .from('delivery_otps')
      .update({ verified_at: new Date().toISOString() })
      .eq('id', codeRow.id)

    await serviceClient
      .from('deliveries')
      .update({ status: 'confirmed', confirmed_at: new Date().toISOString() })
      .eq('id', delivery_id)

    return json({ ok: true })
  } catch (err) {
    console.error('[confirm-delivery-otp]', err)
    return json({ error: (err as Error).message }, 500)
  }
})
