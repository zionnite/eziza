import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { json } from '../_shared/cors.ts'

// Handles Paystack webhook events for Eziza's own customer wallet top-ups
// (separate concern from the tenant-facing dispatch-webhook, which relays
// delivery status changes outward — this one is inbound, from Paystack).
const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
)
const PAYSTACK_SECRET_KEY = Deno.env.get('PAYSTACK_SECRET_KEY')!

async function verifySignature(rawBody: string, signature: string | null): Promise<boolean> {
  if (!signature) return false
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(PAYSTACK_SECRET_KEY),
    { name: 'HMAC', hash: 'SHA-512' },
    false,
    ['sign'],
  )
  const sigBuf = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(rawBody))
  const computed = Array.from(new Uint8Array(sigBuf))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('')
  return computed === signature
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok')

  const rawBody = await req.text()
  const signature = req.headers.get('x-paystack-signature')

  if (!(await verifySignature(rawBody, signature))) {
    return json({ error: 'Invalid signature' }, 401)
  }

  const event = JSON.parse(rawBody)

  if (event.event !== 'charge.success') {
    return json({ ok: true, reason: 'ignored event type' })
  }

  const data = event.data
  const reference = data.reference as string
  const amountKobo = data.amount as number
  const metadata = data.metadata ?? {}
  const customerId = metadata.customer_id as string | undefined
  const purpose = metadata.purpose as string | undefined

  if (purpose !== 'wallet_topup' || !customerId) {
    return json({ ok: true, reason: 'not a wallet top-up' })
  }

  // Idempotent — the unique index on wallet_transactions.reference makes a
  // duplicate webhook delivery (Paystack retries on timeout) a no-op insert
  // failure rather than a double-credit.
  const { error } = await supabase.from('wallet_transactions').insert({
    customer_id: customerId,
    amount: amountKobo / 100,
    type: 'credit',
    description: 'Wallet top-up',
    reference,
  })

  if (error && !error.message.includes('duplicate key')) {
    return json({ error: error.message }, 500)
  }

  return json({ ok: true })
})
