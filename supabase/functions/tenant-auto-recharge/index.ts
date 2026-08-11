import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { json } from '../_shared/cors.ts'

// Fired by a DB trigger (auto_recharge_tenant_wallet(), AFTER UPDATE OF
// wallet_balance ON tenants, via net.http_post) when a tenant's balance
// drops below their own configured threshold with auto-recharge enabled.
// Called with the service-role key as a real Supabase JWT — normal JWT
// verification stays on for this function, no --no-verify-jwt needed.
//
// Reuses the authorization saved from that tenant's own most recent manual
// top-up (paystack-webhook captures it on charge.success) -- never asks the
// tenant for card details again. Crediting itself is NOT done here --
// Paystack's own charge.success webhook fires for this charge exactly like
// any other, and paystack-webhook's existing tenant_topup branch (same
// metadata.purpose) picks it up and credits tenant_wallet_transactions
// with the same idempotent-on-reference shape already proven for manual
// top-ups.
const PAYSTACK_SECRET_KEY = Deno.env.get('PAYSTACK_SECRET_KEY')!
const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
)

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok')

  try {
    const { tenant_id } = await req.json()
    if (!tenant_id) return json({ error: 'tenant_id required' }, 400)

    const { data: tenant } = await supabase
      .from('tenants')
      .select('email, auto_recharge_enabled, auto_recharge_amount, paystack_authorization_code')
      .eq('id', tenant_id)
      .maybeSingle()

    // The trigger already checks these before firing -- re-checked here too
    // since this function could in principle be called directly, not just
    // via the trigger.
    if (!tenant?.auto_recharge_enabled || !tenant.paystack_authorization_code || !tenant.auto_recharge_amount) {
      return json({ ok: false, reason: 'auto-recharge not fully configured for this tenant' })
    }

    const reference = `tenant_autorecharge_${tenant_id}_${Date.now()}`

    const res = await fetch('https://api.paystack.co/transaction/charge_authorization', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${PAYSTACK_SECRET_KEY}`,
      },
      body: JSON.stringify({
        authorization_code: tenant.paystack_authorization_code,
        email:              tenant.email,
        amount:             Math.round(Number(tenant.auto_recharge_amount) * 100),
        currency:           'NGN',
        reference,
        metadata: { tenant_id, purpose: 'tenant_topup', auto_recharge: true },
      }),
    })

    const body = await res.json()
    if (!res.ok || !body.status) {
      return json({ ok: false, error: body.message ?? 'Charge failed' }, 500)
    }

    return json({ ok: true, reference })
  } catch (err) {
    return json({ error: err instanceof Error ? err.message : 'Unknown error' }, 500)
  }
})
