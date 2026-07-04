import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { validateApiKey } from '../_shared/auth.ts'
import { cors, json } from '../_shared/cors.ts'

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
)

const CANCELLABLE = ['open', 'assigned']

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })

  const auth = await validateApiKey(req)
  if (!auth) return json({ error: 'Unauthorized' }, 401)

  try {
    const { delivery_id, reason } = await req.json()
    if (!delivery_id) return json({ error: 'Missing delivery_id' }, 400)

    // Verify ownership + cancellable status
    const { data: delivery } = await supabase
      .from('deliveries')
      .select('id, status, rider_id')
      .eq('id', delivery_id)
      .eq('tenant_id', auth.tenantId)
      .single()

    if (!delivery) return json({ error: 'Delivery not found' }, 404)

    if (!CANCELLABLE.includes(delivery.status)) {
      return json(
        { error: `Cannot cancel a delivery with status '${delivery.status}'` },
        409,
      )
    }

    const { error } = await supabase
      .from('deliveries')
      .update({
        status:       'cancelled',
        cancelled_at: new Date().toISOString(),
        cancel_reason: reason ?? null,
      })
      .eq('id', delivery_id)

    if (error) throw error

    return json({ delivery_id, status: 'cancelled' })
  } catch (err) {
    return json({ error: err.message }, 500)
  }
})
