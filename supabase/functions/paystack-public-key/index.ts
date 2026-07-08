import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { json } from '../_shared/cors.ts'

// Serves the Paystack PUBLIC key to the Flutter app at runtime, so the key
// can rotate without an app release. Public keys are non-sensitive by
// design (they're meant to be embedded in client apps) — no auth needed.
serve((req) => {
  if (req.method === 'OPTIONS') return new Response('ok')
  const key = Deno.env.get('PAYSTACK_PUBLIC_KEY') ?? ''
  return json({ public_key: key })
})
