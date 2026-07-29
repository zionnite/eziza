import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { validateApiKey } from '../_shared/auth.ts'
import { cors, json } from '../_shared/cors.ts'

// ── Tenant-authenticated twin of shipbubble-package-options. Same cached
// proxy for Shipbubble's category/box-size reference data, so a tenant's
// own package picker (e.g. ZeeFashion's "Ready for Pickup" flow) stays in
// sync with Shipbubble's real presets instead of inventing tiers.

const SHIPBUBBLE_BASE = 'https://api.shipbubble.com/v1'

let cache: { categories: unknown; dimensions: unknown; cachedAt: number } | null = null
const CACHE_TTL_MS = 60 * 60 * 1000

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })

  const auth = await validateApiKey(req)
  if (!auth) return json({ error: 'Unauthorized' }, 401)

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
