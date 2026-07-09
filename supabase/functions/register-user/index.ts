import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { cors, json } from '../_shared/cors.ts'

// Creates only the auth user — no rider/company row yet.
// The caller signs in immediately after to get a session.

const admin = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  { auth: { autoRefreshToken: false, persistSession: false } },
)

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })

  try {
    // phone is deliberately not collected at signup anymore -- customers
    // are prompted for it later, at the point they actually need it
    // (Send Package requires a sender phone before submitting).
    const { email, password, fullName } = await req.json()

    if (!email || !password || !fullName) {
      return json({ error: 'Missing required fields' }, 400)
    }

    const { data: { user }, error: authErr } = await admin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: { full_name: fullName },
    })

    if (authErr) {
      const msg = authErr.message.toLowerCase().includes('already registered')
        ? 'This email address is already registered.'
        : authErr.message
      return json({ error: msg }, 400)
    }
    if (!user) return json({ error: 'Failed to create user' }, 500)

    return json({ ok: true })
  } catch (err) {
    return json({ error: err.message }, 500)
  }
})
