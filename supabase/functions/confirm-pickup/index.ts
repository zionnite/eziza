import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { validateApiKey } from '../_shared/auth.ts'
import { cors, json } from '../_shared/cors.ts'

// ── Tenant confirms handoff to rider on behalf of their sender ─────────────
// Used when the sender is a tenant merchant (e.g. ZeeFashion) who confirms
// pickup inside the tenant's own app rather than the Eziza app.

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
)

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })

  const auth = await validateApiKey(req)
  if (!auth) return json({ error: 'Unauthorized' }, 401)

  try {
    const { delivery_id } = await req.json()
    if (!delivery_id) return json({ error: 'Missing delivery_id' }, 400)

    const { data: delivery } = await supabase
      .from('deliveries')
      .select('id, status')
      .eq('id', delivery_id)
      .eq('tenant_id', auth.tenantId)
      .single()

    if (!delivery) return json({ error: 'Delivery not found' }, 404)

    if (delivery.status !== 'awaiting_pickup_confirm') {
      return json(
        { error: `Cannot confirm pickup for a delivery with status '${delivery.status}'` },
        409,
      )
    }

    const { error } = await supabase
      .from('deliveries')
      .update({
        status:        'picked_up',
        picked_up_at:  new Date().toISOString(),
      })
      .eq('id', delivery_id)

    if (error) throw error

    return json({ delivery_id, status: 'picked_up' })
  } catch (err) {
    return json({ error: err.message }, 500)
  }
})
