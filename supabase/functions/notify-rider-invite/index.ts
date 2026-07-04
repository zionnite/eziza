import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { json } from '../_shared/cors.ts'

// Triggered by DB trigger on company_rider_invites INSERT.
// Notifies the invited rider via push that a company wants them to join.

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
)

const notifyUrl = `${Deno.env.get('SUPABASE_URL')}/functions/v1/send-notification`
const authHeader = `Bearer ${Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')}`

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok')

  try {
    const { record } = await req.json()
    const riderId   = record?.rider_id   as string | undefined
    const companyId = record?.company_id as string | undefined
    if (!riderId || !companyId) return json({ ok: true, reason: 'no rider_id or company_id' })

    // Fetch company name
    const { data: company } = await supabase
      .from('companies')
      .select('name')
      .eq('id', companyId)
      .maybeSingle()

    const companyName = company?.name ?? 'A logistics company'

    // Fetch rider's FCM token (device_tokens table, keyed by auth_user_id)
    const { data: tokenRow } = await supabase
      .from('device_tokens')
      .select('token')
      .eq('auth_user_id', riderId)
      .maybeSingle()

    if (!tokenRow?.token) return json({ ok: true, reason: 'no fcm token for rider' })

    await fetch(notifyUrl, {
      method:  'POST',
      headers: { 'Content-Type': 'application/json', Authorization: authHeader },
      body:    JSON.stringify({
        token: tokenRow.token,
        title: '🏢 Company Invite',
        body:  `${companyName} invited you to join their rider fleet.`,
        data:  { type: 'company_invite', company_id: companyId },
      }),
    })

    return json({ ok: true })
  } catch (err) {
    return json({ error: err.message }, 500)
  }
})
