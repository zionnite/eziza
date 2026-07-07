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
    const url        = new URL(req.url)
    const deliveryId = url.searchParams.get('id')
    if (!deliveryId) return json({ error: 'Missing ?id= parameter' }, 400)

    const { data: delivery, error } = await supabase
      .from('deliveries')
      .select(`
        *,
        rider:riders(id, auth_user_id, full_name, phone, vehicle_type, vehicle_plate, rating_avg)
      `)
      .eq('id', deliveryId)
      .eq('tenant_id', auth.tenantId)
      .single()

    if (error || !delivery) return json({ error: 'Delivery not found' }, 404)

    // Include live rider location once a rider is assigned and active.
    // rider_locations.rider_id is the rider's auth.uid() (by design), not
    // riders.id — use the joined rider's auth_user_id to look it up.
    let riderLocation = null
    const riderAuthUserId = delivery.rider?.auth_user_id as string | undefined
    if (riderAuthUserId && ['assigned', 'awaiting_pickup_confirm', 'picked_up'].includes(delivery.status)) {
      const { data: loc } = await supabase
        .from('rider_locations')
        .select('latitude, longitude, updated_at')
        .eq('rider_id', riderAuthUserId)
        .single()
      riderLocation = loc
    }

    return json({ ...delivery, rider_location: riderLocation })
  } catch (err) {
    return json({ error: err.message }, 500)
  }
})
