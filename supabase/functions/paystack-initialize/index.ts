import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { json } from '../_shared/cors.ts'

// Initializes a Paystack transaction SERVER-SIDE (secret key never leaves
// this function) and returns a hosted checkout URL for the client to open.
// The client only ever sees the public key (via paystack-public-key) — see
// PROGRESS.md for why this deliberately does NOT use the pay_with_paystack
// Flutter package, which requires shipping the real secret key to the app.
const PAYSTACK_SECRET_KEY = Deno.env.get('PAYSTACK_SECRET_KEY')!
const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
)

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok')

  try {
    const token = req.headers.get('authorization')?.replace(/^Bearer\s+/i, '')
    if (!token) return json({ error: 'Unauthorized' }, 401)
    const { data: userData, error: userErr } = await supabase.auth.getUser(token)
    if (userErr || !userData?.user) return json({ error: 'Unauthorized' }, 401)

    const { email, amount, customer_id, reference } = await req.json()
    if (!email || !amount || !customer_id || !reference) {
      return json({ error: 'email, amount, customer_id and reference are required' }, 400)
    }
    if (customer_id !== userData.user.id) {
      return json({ error: 'customer_id does not match the authenticated user' }, 403)
    }

    const res = await fetch('https://api.paystack.co/transaction/initialize', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${PAYSTACK_SECRET_KEY}`,
      },
      body: JSON.stringify({
        email,
        amount: Math.round(amount * 100), // kobo
        currency: 'NGN',
        reference,
        metadata: { customer_id, purpose: 'wallet_topup' },
      }),
    })

    const body = await res.json()
    if (!res.ok || !body.status) {
      return json({ error: body.message ?? 'Could not initialize transaction' }, 500)
    }

    return json({
      authorization_url: body.data.authorization_url,
      access_code: body.data.access_code,
      reference: body.data.reference,
    })
  } catch (err) {
    return json({ error: err instanceof Error ? err.message : 'Unknown error' }, 500)
  }
})
