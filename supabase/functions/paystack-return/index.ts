import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'

// Bridge page for the Paystack callback_url. Paystack's /transaction/
// initialize silently ignores a raw custom-scheme callback_url — confirmed
// live (checkout stayed on its own "Payment Successful" screen, no
// navigation attempted). This real https:// page is what Paystack actually
// redirects to.
//
// From here, automatic navigation to eziza://wallet-topup-complete (via
// meta-refresh or JS) is NOT reliable on iOS — Safari/SFSafariViewController
// deliberately blocks non-user-gesture navigation to unrecognized URL
// schemes as an anti-malicious-redirect measure. This is a WebKit platform
// restriction, not something fixable from the page itself. The reliable
// fix is a real tappable button (a genuine user gesture WebKit allows
// through) that auto-taps itself via a synthetic click on load — synthetic
// clicks don't count as user gestures either, so the automatic attempts
// below are a bonus for platforms where they do work (Android is more
// permissive), with the visible button as the fallback that always works.
const html = `<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta http-equiv="refresh" content="0;url=eziza://wallet-topup-complete">
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
  <div class="check">✅</div>
  <h1>Payment Successful</h1>
  <p>Tap below to return to the Eziza app.</p>
  <a class="btn" id="returnBtn" href="eziza://wallet-topup-complete">Return to Eziza</a>
  <script>
    // Best-effort automatic attempts — works on some platforms (Android),
    // harmless where it's blocked (iOS just ignores it and shows the button).
    window.location.href = 'eziza://wallet-topup-complete';
  </script>
</body>
</html>`

serve(() => new Response(html, { headers: { 'Content-Type': 'text/html' } }))
