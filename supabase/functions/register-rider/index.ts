import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { cors, json } from '../_shared/cors.ts'

// Creates the auth user + rider row using the service role key, so this works
// regardless of whether email confirmation is enabled. The caller then signs
// in normally with signInWithPassword to get a session.

const admin = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  { auth: { autoRefreshToken: false, persistSession: false } },
)

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })

  try {
    const {
      email, password, fullName, phone,
      vehicleType, vehiclePlate, coverageStates,
      bankName, accountNumber, accountName,
    } = await req.json()

    if (!email || !password || !fullName || !phone || !vehicleType) {
      return json({ error: 'Missing required fields' }, 400)
    }

    // 1. Create auth user — email marked confirmed so signInWithPassword works immediately
    const { data: { user }, error: authErr } = await admin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
    })

    if (authErr) return json({ error: authErr.message }, 400)
    if (!user)   return json({ error: 'Failed to create user' }, 500)

    // 2. Insert rider row — service role bypasses RLS
    const { error: dbErr } = await admin.from('riders').insert({
      auth_user_id:    user.id,
      full_name:       fullName,
      phone,
      email,
      vehicle_type:    vehicleType,
      vehicle_plate:   vehiclePlate || null,
      coverage_states: coverageStates ?? [],
      bank_name:       bankName       || null,
      account_number:  accountNumber  || null,
      account_name:    accountName    || null,
      is_approved:     false,
    })

    if (dbErr) {
      // Rollback: delete the auth user so the email isn't locked
      await admin.auth.admin.deleteUser(user.id)

      // Translate constraint violations into readable messages
      const msg = dbErr.code === '23505'
        ? dbErr.message.includes('phone')
          ? 'This phone number is already registered.'
          : dbErr.message.includes('email')
          ? 'This email address is already registered.'
          : 'An account with these details already exists.'
        : dbErr.message

      return json({ error: msg }, 400)
    }

    return json({ ok: true })
  } catch (err) {
    return json({ error: err.message }, 500)
  }
})
