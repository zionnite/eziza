import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { json } from '../_shared/cors.ts'

// ── Supabase clients ──────────────────────────────────────────────────────────

const serviceClient = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
)

// ── Helpers ───────────────────────────────────────────────────────────────────

function makeOtp(): string {
  // Cryptographically random 6-digit code
  const arr = new Uint32Array(1)
  crypto.getRandomValues(arr)
  return String(100000 + (arr[0] % 900000))
}

async function sha256hex(text: string): Promise<string> {
  const buf = await crypto.subtle.digest(
    'SHA-256',
    new TextEncoder().encode(text),
  )
  return Array.from(new Uint8Array(buf))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('')
}

/** Normalise Nigerian phone numbers to international format without leading +.
 *  08012345678 → 2348012345678
 *  +2348012345678 → 2348012345678
 */
function normalisePhone(raw: string): string {
  const digits = raw.replace(/\D/g, '')
  if (digits.startsWith('0')) return '234' + digits.slice(1)
  if (digits.startsWith('234')) return digits
  return digits
}

function maskPhone(raw: string): string {
  // Show only last 4 digits: ***-***-4567
  return raw.replace(/\d(?=\d{4})/g, '*')
}

async function sendSms(phone: string, otp: string): Promise<void> {
  const apiKey = Deno.env.get('TERMII_API_KEY')
  if (!apiKey) {
    // Dev / staging — log instead of sending so tests don't require a real key
    console.log(`[DEV] OTP for ${phone}: ${otp}`)
    return
  }
  const res = await fetch('https://api.ng.termii.com/api/sms/send', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      to:      normalisePhone(phone),
      from:    'Eziza',
      sms:     `Your Eziza delivery confirmation code is: ${otp}. Valid for 10 minutes. Do not share this code.`,
      type:    'plain',
      channel: 'generic',
      api_key: apiKey,
    }),
  })
  if (!res.ok) {
    const body = await res.text()
    throw new Error(`SMS failed (${res.status}): ${body}`)
  }
}

// ── Main handler ──────────────────────────────────────────────────────────────

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
    const { action, delivery_id, otp } = body as {
      action:      string
      delivery_id: string
      otp?:        string
    }

    if (!delivery_id) return json({ error: 'delivery_id required' }, 400)

    // Fetch delivery + verify the calling user is the assigned rider
    const { data: delivery } = await serviceClient
      .from('deliveries')
      .select('id, status, delivery_contact_phone, rider_id')
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

    // ── action: send ──────────────────────────────────────────────────────────
    if (action === 'send') {
      if (delivery.status !== 'delivered') {
        return json({ error: 'Delivery must have status "delivered" before requesting OTP' }, 400)
      }

      const phone = delivery.delivery_contact_phone as string | null
      if (!phone?.trim()) {
        return json({ error: 'No recipient phone number on file for this delivery' }, 400)
      }

      const otpCode   = makeOtp()
      const otpHash   = await sha256hex(otpCode)
      const expiresAt = new Date(Date.now() + 10 * 60 * 1000).toISOString()

      // Delete any previous OTPs for this delivery before inserting a fresh one
      await serviceClient.from('delivery_otps').delete().eq('delivery_id', delivery_id)

      const { error: insertErr } = await serviceClient.from('delivery_otps').insert({
        delivery_id,
        otp_hash:   otpHash,
        expires_at: expiresAt,
      })
      if (insertErr) throw insertErr

      let devOtp: string | undefined
      try {
        await sendSms(phone.trim(), otpCode)
      } catch (smsErr) {
        // SMS failed — return the code in the response so the rider can
        // enter it manually (temporary until SMS provider is working).
        console.warn('[confirm-delivery-otp] SMS failed, falling back to dev_otp:', smsErr)
        devOtp = otpCode
      }

      return json({
        ok:           true,
        masked_phone: maskPhone(phone.trim()),
        ...(devOtp ? { dev_otp: devOtp } : {}),
      })
    }

    // ── action: verify ────────────────────────────────────────────────────────
    if (action === 'verify') {
      if (!otp?.trim()) return json({ error: 'otp required' }, 400)

      const { data: otpRow } = await serviceClient
        .from('delivery_otps')
        .select('id, otp_hash, expires_at, attempts, verified_at')
        .eq('delivery_id', delivery_id)
        .order('created_at', { ascending: false })
        .limit(1)
        .maybeSingle()

      if (!otpRow)           return json({ error: 'No OTP found — request a new one.' }, 400)
      if (otpRow.verified_at) return json({ error: 'This delivery is already confirmed.' }, 400)
      if (new Date(otpRow.expires_at) < new Date()) {
        return json({ error: 'OTP expired — tap "Resend code" to get a new one.' }, 400)
      }
      if (otpRow.attempts >= 3) {
        return json({ error: 'Too many incorrect attempts — tap "Resend code" to get a new one.' }, 400)
      }

      const inputHash = await sha256hex(otp.trim())

      // Always increment attempts before checking (prevents timing oracle)
      await serviceClient
        .from('delivery_otps')
        .update({ attempts: otpRow.attempts + 1 })
        .eq('id', otpRow.id)

      if (inputHash !== otpRow.otp_hash) {
        const remaining = 2 - otpRow.attempts
        return json(
          { error: `Incorrect code. ${remaining} attempt${remaining === 1 ? '' : 's'} left.` },
          400,
        )
      }

      // OTP correct — mark verified, confirm delivery
      await serviceClient
        .from('delivery_otps')
        .update({ verified_at: new Date().toISOString() })
        .eq('id', otpRow.id)

      await serviceClient
        .from('deliveries')
        .update({ status: 'confirmed', confirmed_at: new Date().toISOString() })
        .eq('id', delivery_id)

      return json({ ok: true })
    }

    return json({ error: `Unknown action: ${action}` }, 400)
  } catch (err) {
    console.error('[confirm-delivery-otp]', err)
    return json({ error: (err as Error).message }, 500)
  }
})
