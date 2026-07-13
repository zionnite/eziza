import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { validateApiKey } from '../_shared/auth.ts'
import { cors, json } from '../_shared/cors.ts'

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
)

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })

  const auth = await validateApiKey(req)
  if (!auth) return json({ error: 'Unauthorized' }, 401)

  try {
    const body = await req.json()
    const {
      external_order_id,
      external_ref,
      pickup_state,
      pickup_address,
      pickup_lat,
      pickup_lng,
      pickup_contact_name,
      pickup_contact_phone,
      delivery_address,
      delivery_lat,
      delivery_lng,
      delivery_contact_name,
      delivery_contact_phone,
      package_description,
      package_value,
    } = body

    if (!external_order_id || !pickup_address || !delivery_address) {
      return json(
        { error: 'Required: external_order_id, pickup_address, delivery_address' },
        400,
      )
    }

    // Get bid window from settings
    const { data: setting } = await supabase
      .from('settings')
      .select('value')
      .eq('key', 'bid_window_minutes')
      .single()

    const windowMins  = parseInt(setting?.value ?? '30')
    const bidClosesAt = new Date(Date.now() + windowMins * 60 * 1000).toISOString()

    const { data: delivery, error } = await supabase
      .from('deliveries')
      .insert({
        tenant_id: auth.tenantId,
        external_order_id,
        external_ref,
        pickup_state,
        pickup_address,
        pickup_lat,
        pickup_lng,
        pickup_contact_name,
        pickup_contact_phone,
        delivery_address,
        delivery_lat,
        delivery_lng,
        delivery_contact_name,
        delivery_contact_phone,
        package_description,
        package_value,
        status: 'open',
        bid_closes_at: bidClosesAt,
        is_sandbox: auth.mode === 'sandbox',
      })
      .select('id, status, bid_closes_at')
      .single()

    if (error) throw error

    return json(
      {
        delivery_id:   delivery.id,
        status:        delivery.status,
        bid_closes_at: delivery.bid_closes_at,
      },
      201,
    )
  } catch (err) {
    return json({ error: err.message }, 500)
  }
})
