import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { cors, json } from '../_shared/cors.ts'

// Manually re-dispatch a previously logged webhook attempt. Called
// server-to-server by eziza-partners' /api/tenant/webhook-log/replay route
// (using the service-role key as its bearer token, verified by this
// function's normal JWT verification -- not exposed to tenants directly).
// Ownership (does this log row belong to the calling tenant?) is checked by
// the caller before it ever reaches here; this function trusts log_id alone.

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
)

const WEBHOOK_SECRET = Deno.env.get('WEBHOOK_SIGNING_SECRET') ?? ''

async function sign(payload: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(WEBHOOK_SECRET),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  )
  const sig = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(payload))
  return Array.from(new Uint8Array(sig))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('')
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })

  try {
    const { log_id } = await req.json()
    if (!log_id) return json({ error: 'Missing log_id' }, 400)

    const { data: logRow } = await supabase
      .from('webhook_dispatch_log')
      .select('id, delivery_id, tenant_id, event, payload')
      .eq('id', log_id)
      .single()

    if (!logRow) return json({ error: 'Log entry not found' }, 404)

    const { data: tenant } = await supabase
      .from('tenants')
      .select('webhook_url, is_active')
      .eq('id', logRow.tenant_id)
      .single()

    if (!tenant?.webhook_url) return json({ error: 'Tenant has no webhook URL configured' }, 409)
    if (!tenant.is_active) return json({ error: 'Tenant is deactivated' }, 409)

    // Re-serialize the stored payload fresh -- the signature only needs to
    // match the bytes we're about to send, not the original dispatch attempt.
    const payload   = JSON.stringify(logRow.payload)
    const signature = await sign(payload)

    let responseStatus: number | null = null
    let errorMsg: string | null       = null

    try {
      const res = await fetch(tenant.webhook_url, {
        method:  'POST',
        headers: {
          'Content-Type':      'application/json',
          'X-Eziza-Signature': signature,
          'X-Eziza-Event':     logRow.event,
          'X-Eziza-Replay':    'true',
        },
        body: payload,
      })
      responseStatus = res.status
    } catch (fetchErr) {
      errorMsg = fetchErr.message
    }

    await supabase.from('webhook_dispatch_log').insert({
      delivery_id:     logRow.delivery_id,
      tenant_id:       logRow.tenant_id,
      event:           logRow.event,
      payload:         logRow.payload,
      response_status: responseStatus,
      error:           errorMsg,
    })

    return json({ ok: true, response_status: responseStatus, error: errorMsg })
  } catch (err) {
    return json({ error: err.message }, 500)
  }
})
