import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { json } from '../_shared/cors.ts'

// Tenant-facing twin of paystack-initialize (which is customer-facing).
// Same shape: verifies the caller's own Supabase session JWT (the tenant
// contact's real login, forwarded as-is by eziza-partners — not an API
// key), then initializes a Paystack transaction server-side so
// PAYSTACK_SECRET_KEY never has to be duplicated into eziza-partners' own
// env. paystack-webhook (already deployed, already has this key) handles
// the credit on charge.success via the tenant_topup purpose.
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

    const { data: tenant } = await supabase
      .from('tenants')
      .select('id, is_active')
      .eq('auth_user_id', userData.user.id)
      .maybeSingle()
    if (!tenant?.is_active) return json({ error: 'Unauthorized' }, 401)

    const { amount, email, callback_url } = await req.json()
    if (typeof amount !== 'number' || !(amount > 0)) {
      return json({ error: 'amount must be a positive number' }, 400)
    }
    if (!callback_url || typeof callback_url !== 'string') {
      return json({ error: 'callback_url is required' }, 400)
    }

    const reference = `tenant_topup_${tenant.id}_${Date.now()}`

    const res = await fetch('https://api.paystack.co/transaction/initialize', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${PAYSTACK_SECRET_KEY}`,
      },
      body: JSON.stringify({
        email: email || userData.user.email || 'tenant@eziza.online',
        amount: Math.round(amount * 100), // kobo
        currency: 'NGN',
        reference,
        metadata: { tenant_id: tenant.id, purpose: 'tenant_topup' },
        callback_url,
      }),
    })

    const body = await res.json()
    if (!res.ok || !body.status) {
      return json({ error: body.message ?? 'Could not initialize transaction' }, 500)
    }

    return json({
      authorization_url: body.data.authorization_url,
      reference: body.data.reference,
    })
  } catch (err) {
    return json({ error: err instanceof Error ? err.message : 'Unknown error' }, 500)
  }
})
