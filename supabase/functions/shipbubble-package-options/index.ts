import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { cors, json } from '../_shared/cors.ts'

// ── Thin cached proxy for Shipbubble's reference-data endpoints ──────────
// Client picks a category + box size at booking time (fetch_rates requires
// both); proxied so the Shipbubble key stays server-side, same reasoning
// as every other secret-holding function in this project.

const SHIPBUBBLE_BASE = 'https://api.shipbubble.com/v1'

// Small, near-static reference lists -- module-level cache survives across
// invocations on a warm instance, harmless to recompute on a cold one.
let cache: { categories: unknown; dimensions: unknown; cachedAt: number } | null = null
const CACHE_TTL_MS = 60 * 60 * 1000 // 1 hour

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })

  const authHeader = req.headers.get('Authorization')
  if (!authHeader) return json({ error: 'Unauthorized' }, 401)

  const userClient = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: authHeader } } },
  )
  const { data: { user }, error: authErr } = await userClient.auth.getUser()
  if (authErr || !user) return json({ error: 'Unauthorized' }, 401)

  const apiKey = Deno.env.get('SHIPBUBBLE_API_KEY')
  if (!apiKey) return json({ error: 'Shipbubble is not configured yet' }, 503)

  try {
    if (cache && Date.now() - cache.cachedAt < CACHE_TTL_MS) {
      return json({ categories: cache.categories, dimensions: cache.dimensions })
    }

    const headers = { 'Authorization': `Bearer ${apiKey}`, 'Accept': 'application/json' }

    const [catRes, dimRes] = await Promise.all([
      fetch(`${SHIPBUBBLE_BASE}/shipping/labels/categories`, { headers }),
      fetch(`${SHIPBUBBLE_BASE}/shipping/labels/boxes`, { headers }),
    ])

    if (!catRes.ok || !dimRes.ok) {
      const catBody = await catRes.text()
      const dimBody = await dimRes.text()
      throw new Error(`Shipbubble reference data failed: categories(${catRes.status})=${catBody} boxes(${dimRes.status})=${dimBody}`)
    }

    const categories = await catRes.json()
    const dimensions = await dimRes.json()
    cache = { categories, dimensions, cachedAt: Date.now() }

    return json({ categories, dimensions })
  } catch (err) {
    return json({ error: (err as Error).message }, 500)
  }
})
