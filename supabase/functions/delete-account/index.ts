import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { json } from '../_shared/cors.ts'

// Apple App Store Guideline 5.1.1(v): apps that support account creation
// must offer in-app account deletion. This is that.
//
// IMPORTANT -- does NOT hard-delete auth.users, and does NOT rely on
// admin.deleteUser's `should_soft_delete` option. Both were tested against
// this project's actual schema with a throwaway account that had delivery/
// wallet history attached, and both attempt a real DELETE under the hood:
//   - customers.id -> auth.users(id) ON DELETE CASCADE, but
//     wallet_transactions.customer_id -> customers(id) ON DELETE NO ACTION
//   - riders.auth_user_id has no live FK to auth.users left (empirically:
//     surviving as NULL rather than cascading), but that's incidental --
//     not something to depend on.
// The moment a user has any wallet_transactions row (true for anyone who's
// ever paid for or been paid for a delivery -- the common case), any
// attempt to delete or cascade-touch auth.users fails outright with a
// foreign-key violation (verified: 500, "violates foreign key constraint
// wallet_transactions_customer_id_fkey"). So instead:
//   1. Anonymise PII on customers/riders/companies (rows survive --
//      required for delivery/bid/earnings/wallet history integrity, which
//      other parties and the business have a legitimate ongoing interest
//      in, e.g. a completed delivery's other party, financial records).
//   2. Permanently ban the auth user (ban_duration far in the future) --
//      login becomes impossible forever, with zero risk of an FK cascade
//      since nothing is ever deleted at the auth.users row.
// This is the same trade-off ride-sharing/delivery apps commonly make for
// exactly this reason, and satisfies "delete my account" from the user's
// side: they can never sign in again, and no personally-identifying data
// they entered is visible anywhere in the app afterward.
//
// riders.phone and companies.email/phone/contact_person are all NOT NULL --
// found live (an early version of this function set them to null, which
// silently failed the whole UPDATE since the error wasn't checked). Uses
// '' instead of null for those specific columns.

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
    const uid = userData.user.id

    // customers row always exists (Phase 3's auto-creation trigger fires
    // for every auth.users insert, rider/company/customer alike).
    const { error: custErr } = await supabase.from('customers').update({
      full_name: 'Deleted User',
      phone: null,
      avatar_url: null,
      pin: null,
      pin_set: false,
    }).eq('id', uid)
    if (custErr) return json({ error: `customers: ${custErr.message}` }, 500)

    const { data: rider } = await supabase
      .from('riders').select('id').eq('auth_user_id', uid).maybeSingle()
    if (rider) {
      const { error: riderErr } = await supabase.from('riders').update({
        full_name: 'Deleted Rider',
        phone: '',
        email: null,
        avatar_url: null,
        gov_id_url: null,
        selfie_url: null,
        vehicle_plate: null,
        bank_name: null,
        bank_code: null,
        account_number: null,
        account_name: null,
        fcm_token: null,
        is_available: false,
      }).eq('id', rider.id)
      if (riderErr) return json({ error: `riders: ${riderErr.message}` }, 500)
    }

    const { data: company } = await supabase
      .from('companies').select('id').eq('auth_user_id', uid).maybeSingle()
    if (company) {
      const { error: companyErr } = await supabase.from('companies').update({
        name: 'Deleted Company',
        email: '',
        phone: '',
        contact_person: '',
        cac_number: null,
        city: null,
        avatar_url: null,
        bank_name: null,
        bank_code: null,
        account_number: null,
        account_name: null,
      }).eq('id', company.id)
      if (companyErr) return json({ error: `companies: ${companyErr.message}` }, 500)
    }

    await supabase.from('device_tokens').delete().eq('auth_user_id', uid)

    // ~100 years -- GoTrue has no literal "forever", this is the accepted
    // convention for a permanent ban.
    const { error: banErr } = await supabase.auth.admin.updateUserById(uid, {
      ban_duration: '876000h',
    })
    if (banErr) return json({ error: banErr.message }, 500)

    return json({ ok: true })
  } catch (err) {
    return json({ error: (err as Error).message }, 500)
  }
})
