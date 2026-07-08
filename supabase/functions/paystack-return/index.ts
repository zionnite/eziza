import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'

// Bridge page for the Paystack callback_url. Paystack's /transaction/
// initialize appears to silently ignore a raw custom-scheme callback_url
// (e.g. eziza://...) — confirmed via a live test where the checkout page
// stayed on its own "Payment Successful" screen with no further navigation
// attempted at all. Pointing callback_url at this real https:// page
// instead, which immediately redirects to the custom scheme client-side,
// is the standard fix: iOS/Android DO intercept an in-page navigation to
// an unrecognized scheme from inside SFSafariViewController/Custom Tabs,
// handing control back to the app — it's specifically the server-side
// callback_url field that needs to be a real URL.
const html = `<!DOCTYPE html>
<html>
<head>
  <meta http-equiv="refresh" content="0;url=eziza://wallet-topup-complete">
  <script>window.location.href = 'eziza://wallet-topup-complete';</script>
  <style>
    body { font-family: -apple-system, sans-serif; display: flex; align-items: center;
           justify-content: center; height: 100vh; margin: 0; color: #1A1A2E; text-align: center; }
  </style>
</head>
<body>
  <p>Payment complete. Returning to Eziza…</p>
</body>
</html>`

serve(() => new Response(html, { headers: { 'Content-Type': 'text/html' } }))
