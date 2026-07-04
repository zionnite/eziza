import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { cors, json } from '../_shared/cors.ts'

// Module-level cache — valid within a single function instance lifetime
let _cached: Bank[] | null = null

interface Bank { name: string; code: string }

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })

  if (_cached) return json({ banks: _cached })

  const secret = Deno.env.get('PAYSTACK_SECRET_KEY')
  if (!secret) return json({ error: 'PAYSTACK_SECRET_KEY not set' }, 500)

  try {
    const res = await fetch(
      'https://api.paystack.co/bank?country=nigeria&currency=NGN&use_cursor=false&perPage=100',
      { headers: { Authorization: `Bearer ${secret}` } },
    )

    if (!res.ok) {
      return json({ error: `Paystack returned ${res.status}` }, 502)
    }

    const payload = await res.json()
    if (!payload.status) {
      return json({ error: payload.message ?? 'Paystack error' }, 502)
    }

    _cached = (payload.data as Record<string, string>[]).map((b) => ({
      name: b.name,
      code: b.code,
    }))

    return json({ banks: _cached })
  } catch (e) {
    return json({ error: (e as Error).message }, 500)
  }
})
