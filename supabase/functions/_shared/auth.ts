import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
)

export async function validateApiKey(
  req: Request,
): Promise<{ tenantId: string } | null> {
  const auth = req.headers.get('Authorization')
  if (!auth?.startsWith('Bearer ')) return null

  const rawKey = auth.slice(7)

  // Hash the raw key with SHA-256 — plaintext never stored
  const hash = await crypto.subtle.digest(
    'SHA-256',
    new TextEncoder().encode(rawKey),
  )
  const keyHash = Array.from(new Uint8Array(hash))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('')

  const { data: key } = await supabase
    .from('api_keys')
    .select('id, tenant_id, is_active')
    .eq('key_hash', keyHash)
    .single()

  if (!key?.is_active) return null

  // Fire-and-forget last_used_at update
  supabase
    .from('api_keys')
    .update({ last_used_at: new Date().toISOString() })
    .eq('id', key.id)
    .then(() => {})

  return { tenantId: key.tenant_id }
}
