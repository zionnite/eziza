import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { json } from '../_shared/cors.ts'

// One-off reconciliation helper: lists recent Paystack transactions so a
// payment that succeeded before the webhook was registered can be found
// and manually credited. Admin-only. Not wired into the app.
// TODO: delete once the stuck-payment backlog (if any) is cleared.
const PAYSTACK_SECRET_KEY = Deno.env.get('PAYSTACK_SECRET_KEY')!
const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
)

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok')

  const token = req.headers.get('authorization')?.replace(/^Bearer\s+/i, '')
  if (!token) return json({ error: 'Unauthorized' }, 401)
  const { data: userData, error: userErr } = await supabase.auth.getUser(token)
  if (userErr || !userData?.user) return json({ error: 'Unauthorized' }, 401)

  const { data: admin } = await supabase
    .from('admin_profiles')
    .select('id')
    .eq('id', userData.user.id)
    .eq('is_active', true)
    .maybeSingle()
  if (!admin) return json({ error: 'Unauthorized' }, 401)

  const res = await fetch('https://api.paystack.co/transaction?perPage=20', {
    headers: { Authorization: `Bearer ${PAYSTACK_SECRET_KEY}` },
  })
  const body = await res.json()
  if (!res.ok) return json({ error: body.message ?? 'Could not list transactions' }, 500)

  const transactions = (body.data ?? []).map((t: Record<string, unknown>) => ({
    reference: t.reference,
    amount: (t.amount as number) / 100,
    status: t.status,
    paid_at: t.paid_at,
    customer_email: (t.customer as Record<string, unknown> | null)?.email,
    metadata: t.metadata,
  }))

  return json({ transactions })
})
