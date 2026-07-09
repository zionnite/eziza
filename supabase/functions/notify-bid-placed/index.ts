import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { json } from '../_shared/cors.ts'

// Triggered by Supabase DB webhook on delivery_bids INSERT.
// Notifies the customer that a new offer has arrived on their delivery.
//
// Supabase Dashboard → Database → Webhooks → New:
//   Table: delivery_bids, Event: INSERT, URL: .../functions/v1/notify-bid-placed

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
    const deliveryId = record?.delivery_id as string | undefined
    if (!deliveryId) return json({ ok: true, reason: 'no delivery_id' })

    // Fetch the delivery to find the customer
    const { data: delivery } = await supabase
      .from('deliveries')
      .select('customer_id, pickup_address')
      .eq('id', deliveryId)
      .maybeSingle()

    if (!delivery?.customer_id) return json({ ok: true, reason: 'no customer_id' })

    // Fetch the customer's FCM token
    const { data: tokenRow } = await supabase
      .from('device_tokens')
      .select('token')
      .eq('auth_user_id', delivery.customer_id)
      .maybeSingle()

    if (!tokenRow?.token) return json({ ok: true, reason: 'no token' })

    await fetch(notifyUrl, {
      method:  'POST',
      headers: { 'Content-Type': 'application/json', Authorization: authHeader },
      body:    JSON.stringify({
        token: tokenRow.token,
        title: '📬 New Offer Received',
        body:  'Someone has made an offer on your delivery request.',
        data:  { type: 'bid_placed', delivery_id: deliveryId },
      }),
    })

    return json({ ok: true })
  } catch (err) {
    return json({ error: err.message }, 500)
  }
})
