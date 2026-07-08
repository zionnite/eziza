import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'

// Bridge page for the Paystack callback_url. Paystack's /transaction/
// initialize silently ignores a raw custom-scheme callback_url — confirmed
// live (checkout stayed on its own "Payment Successful" screen, no
// navigation attempted). This real https:// page is what Paystack actually
// redirects to.
//
// Deliberately does NOT attempt an automatic redirect (no meta-refresh, no
// inline script navigation): (1) iOS Safari blocks non-user-gesture
// navigation to unrecognized URL schemes anyway, so it never helped there,
// and (2) live-tested it caused a WebView rendering glitch — the instant
// (content="0") meta-refresh raced the initial paint and the browser fell
// back to showing raw page source as plain text instead of rendering it.
// A plain visible button avoids both problems: a real tap is a genuine
// user gesture that reliably triggers the scheme handoff, and there's no
// redirect race to trip over.
const html = `<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    body { font-family: -apple-system, sans-serif; display: flex; flex-direction: column;
           align-items: center; justify-content: center; height: 100vh; margin: 0;
           color: #1A1A2E; text-align: center; padding: 24px; box-sizing: border-box; }
    .check { font-size: 56px; margin-bottom: 8px; }
    h1 { font-size: 20px; margin: 0 0 8px; }
    p { color: #6b7280; font-size: 14px; margin: 0 0 28px; }
    a.btn { display: inline-block; background: #6C3483; color: #fff; text-decoration: none;
            font-weight: 700; font-size: 16px; padding: 16px 32px; border-radius: 12px; }
  </style>
</head>
<body>
  <div class="check">&#9989;</div>
  <h1>Payment Successful</h1>
  <p>Tap below to return to the Eziza app.</p>
  <a class="btn" href="eziza://wallet-topup-complete">Return to Eziza</a>
</body>
</html>`

serve(() => new Response(html, { headers: { 'Content-Type': 'text/html; charset=utf-8' } }))
