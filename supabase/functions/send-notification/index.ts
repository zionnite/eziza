import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { json } from '../_shared/cors.ts'

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
)

// Sends a push notification to a single FCM device token using the HTTP v1 API.
// Expects env var FIREBASE_SERVICE_ACCOUNT (JSON string of the Firebase service account).
//
// Body: { token: string, title: string, body: string, data?: Record<string, string> }

interface ServiceAccount {
  project_id: string
  client_email: string
  private_key: string
}

// ── JWT / OAuth2 helpers ──────────────────────────────────────────

function pemToDer(pem: string): ArrayBuffer {
  // Handle both literal '\n' (from secrets storage) and real newlines
  const clean = pem.replace(/\\n/g, '\n')
  const b64 = clean
    .split('\n')
    .filter((l) => l.trim() && !l.startsWith('-----'))
    .join('')
  const binary = atob(b64)
  const bytes = new Uint8Array(binary.length)
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i)
  return bytes.buffer
}

function b64urlEncode(value: string | Uint8Array): string {
  const b64 =
    typeof value === 'string'
      ? btoa(value)
      : btoa(String.fromCharCode(...value))
  return b64.replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_')
}

async function getAccessToken(sa: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000)

  const header  = b64urlEncode(JSON.stringify({ alg: 'RS256', typ: 'JWT' }))
  const payload = b64urlEncode(
    JSON.stringify({
      iss:   sa.client_email,
      scope: 'https://www.googleapis.com/auth/firebase.messaging',
      aud:   'https://oauth2.googleapis.com/token',
      iat:   now,
      exp:   now + 3600,
    }),
  )

  const signingInput = `${header}.${payload}`

  const privateKey = await crypto.subtle.importKey(
    'pkcs8',
    pemToDer(sa.private_key),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  )

  const sigBytes = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    privateKey,
    new TextEncoder().encode(signingInput),
  )

  const jwt = `${signingInput}.${b64urlEncode(new Uint8Array(sigBytes))}`

  const tokenRes = await fetch('https://oauth2.googleapis.com/token', {
    method:  'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body:    new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion:  jwt,
    }),
  })

  if (!tokenRes.ok) {
    const err = await tokenRes.text()
    throw new Error(`OAuth2 token exchange failed: ${err}`)
  }

  const { access_token } = await tokenRes.json()
  return access_token as string
}

// ── Main handler ─────────────────────────────────────────────────

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok')

  try {
    const { token: rawToken, user_id, title, body, data } = await req.json() as {
      token?:   string
      user_id?: string
      title:    string
      body:     string
      data?:    Record<string, string>
    }

    if (!title || !body) {
      return json({ error: 'title and body are required' }, 400)
    }

    // Resolve FCM token — caller can pass the token directly (legacy) or
    // a user_id and we look it up from device_tokens (ZeeFashion-style pattern).
    let token = rawToken
    if (!token && user_id) {
      const { data: dt } = await supabase
        .from('device_tokens')
        .select('token')
        .eq('auth_user_id', user_id)
        .maybeSingle()
      token = dt?.token
    }

    if (!token) {
      return json({ ok: true, reason: 'no_token' })
    }

    const saRaw = Deno.env.get('FIREBASE_SERVICE_ACCOUNT')
    if (!saRaw) return json({ error: 'FIREBASE_SERVICE_ACCOUNT not set' }, 500)

    const sa = JSON.parse(saRaw) as ServiceAccount
    const accessToken = await getAccessToken(sa)

    const message: Record<string, unknown> = {
      token,
      notification: { title, body },
      android: {
        priority: 'high',
        notification: { channel_id: 'eziza_jobs', sound: 'default' },
      },
      apns: {
        payload: { aps: { sound: 'default', badge: 1 } },
      },
    }

    if (data && Object.keys(data).length > 0) message.data = data

    const fcmRes = await fetch(
      `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`,
      {
        method:  'POST',
        headers: {
          Authorization:  `Bearer ${accessToken}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ message }),
      },
    )

    const fcmBody = await fcmRes.json()
    if (!fcmRes.ok) return json({ error: fcmBody }, fcmRes.status)

    return json({ ok: true, name: fcmBody.name })
  } catch (err) {
    return json({ error: err.message }, 500)
  }
})
