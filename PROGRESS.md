# Eziza — Progress Tracker

## ✅ Completed

### Foundation
- [x] Supabase project created (`nvwpsccleewgirlwokys.supabase.co`)
- [x] Full DB schema live — `tenants`, `api_keys`, `riders`, `companies`, `company_riders`, `deliveries`, `delivery_bids`, `delivery_status_history`, `rider_locations`, `delivery_ratings`, `rider_payout_requests`, `webhook_dispatch_log`, `settings`
- [x] RLS enabled + policies set
- [x] Realtime enabled on `deliveries`, `delivery_bids`, `rider_locations`
- [x] ZeeFashion added as first tenant
- [x] ZeeFashion API key generated + inserted into `api_keys`

### Edge Functions
- [x] `create-delivery` — tenant requests a pickup
- [x] `get-delivery` — track status + live rider location
- [x] `cancel-delivery` — cancel open/assigned deliveries
- [x] `dispatch-webhook` — fires on delivery status change → POSTs signed event to tenant webhook URL
- [x] DB Webhook configured: `deliveries` UPDATE → `dispatch-webhook`
- [x] `WEBHOOK_SIGNING_SECRET` secret set in Supabase
- [x] `confirm-delivery-otp` — OTP generation + SMS (Termii) + SHA-256 hash verify + delivery confirm

### ZeeFashion Integration
- [x] `logistics-gateway` edge function written (outbound + webhook receiver)
- [x] Migration `20260630000000` — adds `eziza_delivery_id`, `eziza_rider_id`, `agreed_price` to `delivery_requests`
- [x] ZeeFashion secrets added: `EZIZA_URL`, `EZIZA_API_KEY`, `EZIZA_WEBHOOK_SECRET`
- [x] `logistics-gateway` deployed in ZeeFashion
- [x] Migration `20260630000000` run in ZeeFashion Supabase
- [x] "Ready for Pickup" button wired → calls `logistics-gateway` with `action: request_delivery` (behind `FeatureFlags.eziza`)
- [x] `FeatureFlags.eziza` added — reads `eziza_enabled` from `app_settings` DB column (default `false`)
- [x] Admin panel toggle added for `eziza_enabled` in ZeeFashion admin → App Settings
- [x] Migration `20260701000000` — adds `eziza_enabled` column to ZeeFashion `app_settings`

---

### Flutter Rider App — All Screens

#### Auth
- [x] `LoginPage` — email/password login, role detection, routes to correct dashboard
- [x] `RegisterPage` — create account (rider / company / customer)

#### Rider Flow
- [x] `rider_application_page.dart` — multi-step onboarding: personal info, vehicle details, bank details. Submitted for admin approval; rider sees "Application Under Review" until approved
- [x] `rider_dashboard_page.dart` — 4 tabs: Home (active delivery card, online/offline toggle, foreground GPS service), Jobs (job board + bid sheet), Earnings, Profile. Company invites + payout requests
- [x] `rider_map_page.dart` — live GPS navigation during active delivery. OSRM route polyline, ETA, pickup (gold) and dropoff (purple) markers, Confirm Pickup → Confirm Delivery flow. OTP sheet on delivery confirmation. Updates foreground notification text. Upserts rider GPS to `rider_locations`. Auto-closes when customer confirms receipt or OTP verified
- [x] `job_board_page.dart` — open deliveries within rider's coverage area; bid submission sheet
- [x] `active_delivery_page.dart` — full delivery detail + status stepper + action buttons
- [x] `earnings_page.dart` — wallet balance, completed deliveries list, Request Payout flow

#### Company Flow
- [x] `company_registration_page.dart` — 3-level location picker (State → City → Area) from admin-managed `locations` table via `CoverageLocationService`. Bank picker via `BankService`
- [x] `company_dashboard_page.dart` — 3 tabs: Deliveries (bid placement, rider assignment, realtime), Riders (manage fleet, invite riders), Earnings (payout requests). Realtime updates throughout
- [x] `company_map_page.dart` — Fleet overview map. All company riders shown simultaneously with live GPS dots, color-coded OSRM route polylines, destination markers. "Fleet Map" button in Riders tab. Online/Stale/Offline status chips in bottom panel. 30-second refresh timer

#### Customer Flow
- [x] `home_page.dart` "Send & Receive Packages" → saves customer role to Supabase metadata → Obx routing navigates to CustomerDashboardPage
- [x] `customer_dashboard_page.dart` — full dashboard:
  - Stats row (Awaiting Bid / In Transit / Completed / Incoming to confirm)
  - Two CTA cards side-by-side: **Send a Package** + **Track a Package**
  - Two FABs: purple Send Package (bottom) + teal Find Package (top)
  - **Active** tab — sender's live deliveries
  - **History** tab — sender's completed/cancelled deliveries
  - **Incoming** tab — deliveries addressed to this user (by phone match OR tracking code claim). "Find Package by ID" banner always visible at top
  - Realtime channel (no filter, RLS handles visibility for both sent and incoming)
- [x] `send_package_page.dart` — delivery request form with map-based pickup and dropoff selection
- [x] `location_picker_sheet.dart` — reusable map picker with drag-to-pin, GPS, Nominatim reverse geocode
- [x] `my_deliveries_page.dart` — list of customer's deliveries with status chips
- [x] `customer_delivery_detail_page.dart`:
  - `isRecipient` flag — hides bid flow, pickup-handoff action; shows "Incoming Delivery" banner
  - Sender header: shows unique **tracking code** (tap to copy — share with recipient)
  - Confirm Receipt works for both sender and recipient (RLS allows both)
- [x] `delivery_tracking_page.dart`:
  - `isRecipient` flag — hides "Confirm Handoff" button for recipients
  - Live map tracking: pulsing gold rider dot, OSRM ETA, Realtime GPS
  - Confirm Receipt button when status = `delivered`

#### OTP Delivery Confirmation ✅ (was pending — now complete)
- [x] `confirm-delivery-otp` edge function:
  - `action: send` — validates rider owns delivery, generates 6-digit OTP, SHA-256 hashes it, stores in `delivery_otps`, sends SMS via Termii. If SMS fails (e.g. invalid API key), catches error and returns `dev_otp` in response for testing
  - `action: verify` — checks hash, increments attempts before compare (timing-safe), marks `verified_at`, updates delivery to `confirmed`
- [x] `delivery_otps` table — `delivery_id`, `otp_hash`, `expires_at`, `attempts` (max 3), `verified_at`
- [x] `rider_map_page.dart` OTP sheet:
  - Shows after rider taps "Delivered"
  - 6-digit numeric input, auto-submit on full entry
  - Resend with 30s initial cooldown, 60s after resend
  - Amber dev banner shows OTP when SMS is unavailable (testing fallback)
  - `_closing` boolean guard prevents double-close race (OTP verify + Realtime `confirmed` both fire simultaneously)
  - On page open: if delivery already `delivered` (e.g. app restarted), OTP sheet auto-shown via `addPostFrameCallback`
- [x] **Termii API key issue** — both keys currently rejected (401). SMS fails gracefully; dev_otp shown on screen for testing. Awaiting Termii support response

#### Recipient Tracking & Confirmation ✅ (new this session)

**Three independent paths — any one is enough:**

| Path | How it works |
|---|---|
| **Phone match** | User's profile phone = `delivery_contact_phone` (normalized: 08x ↔ 234x) |
| **Tracking code claim** | Recipient enters 6-char code; one RPC auto-claims delivery |
| **OTP** | Rider collects verbal code, enters it; works for everyone |

- [x] **Migration `20260705000002`** — `normalize_phone()` SQL function + RLS policies: `recipient_can_read_delivery` + `recipient_can_confirm_receipt` (phone-based)
- [x] **Migration `20260705000003`** — `recipient_auth_id uuid` column on `deliveries` + RLS policies: `claimed_recipient_can_read_delivery` + `claimed_recipient_can_confirm_receipt`
- [x] **Migration `20260705000004`** — `tracking_code text UNIQUE NOT NULL` on `deliveries`:
  - `generate_tracking_code()` — 6-char code from `ABCDEFGHJKMNPQRSTUVWXYZ23456789` (no ambiguous chars O/0/I/1/L)
  - `set_tracking_code()` trigger — auto-generates on INSERT
  - Backfills all existing deliveries
  - Drops old `preview_delivery` / `claim_delivery` functions
  - `find_and_claim_delivery(code text)` SECURITY DEFINER — looks up by tracking code, sets `recipient_auth_id = uid` atomically; idempotent; rejects own deliveries and already-claimed-by-others
- [x] **Incoming tab** in customer dashboard — shows deliveries from both phone-match RLS and claimed-by-ID RLS
- [x] **"Find Package by ID"** bottom sheet — large centered 6-char input, single RPC call (find + claim in one step, no confirm button), success card shows route/status/code + "View & Track Delivery" button
- [x] **Recipient tracking** — `DeliveryTrackingPage(isRecipient: true)` hides sender-only actions; recipients see same live map, ETA, and rider location as senders
- [x] **Incoming delivery cards** — teal "Track Live" button for in-transit; gold "Confirm Receipt" button when delivered
- [x] **Sender copy ID** — tracking code shown as styled chip in delivery header; tap copies to clipboard with "share with recipient" hint

#### Stats Bug Fixes
- [x] **Customer dashboard Realtime** — changed from client-side `customer_id != uid` guard to server-side `PostgresChangeFilter` (events were silently dropped)
- [x] **Company rider completed count** — `_jobHistory` query was including `delivered` status, causing count to jump when rider marked delivered instead of when customer confirmed. Fixed to query `status = 'confirmed'` only

#### Services / Models
- [x] `lib/models/location.dart` — Location model (State/City/Area)
- [x] `lib/services/coverage_location_service.dart` — fetches admin-managed locations with in-memory cache
- [x] `lib/services/location_service.dart` — GPS tracking
- [x] `lib/services/rider_location_task.dart` — foreground task callback

#### Database Migrations (applied to Eziza Supabase)
- [x] `20260701000000_add_fcm_token.sql`
- [x] `20260701000001_notify_new_job_webhook.sql`
- [x] `20260701000002_riders_doc_urls.sql`
- [x] `20260701000003_unified_schema.sql`
- [x] `20260701000004_payout_bids_rls.sql`
- [x] `20260701000005_deliveries_latlng.sql`
- [x] `20260702000001_locations.sql`
- [x] `20260702000002_company_dashboard.sql`
- [x] `20260702000003_customer_flow.sql`
- [x] `20260702000004_fix_rls_recursion.sql`
- [x] `20260702000005_bids_customer_id.sql`
- [x] `20260702000006_companies_missing_cols.sql`
- [x] `20260702000007_status_history_rls.sql`
- [x] `20260702000008_enable_realtime.sql`
- [x] `20260702000009_delivery_update_webhooks.sql`
- [x] `20260702000010_rider_locations_realtime.sql`
- [x] `20260703000001_riders_public_read.sql`
- [x] `20260704000001_notifications.sql`
- [x] `20260704000002_notify_bid_placed_webhook.sql`
- [x] `20260704000003_companies_status.sql`
- [x] `20260704000004_fix_rider_locations_fk.sql`
- [x] `20260704000005_pickup_state.sql`
- [x] `20260704000006_seed_locations.sql`
- [x] `20260704000007_companies_contact_bank_code.sql`
- [x] `20260704000008_invite_realtime_webhook.sql`
- [x] `20260704000009_bids_rider_nullable.sql`
- [x] `20260704000010_bids_unique_constraints.sql`
- [x] `20260705000001_delivery_otps.sql`
- [x] `20260705000002_incoming_deliveries.sql` — phone-match RLS for recipients
- [x] `20260705000003_claim_delivery.sql` — `recipient_auth_id` + RLS + old preview/claim functions
- [x] `20260705000004_tracking_code.sql` — unique tracking codes + `find_and_claim_delivery` RPC

#### Push Notifications
- [x] `send-notification` edge function — FCM HTTP v1 API with JWT signing
- [x] `notify-new-job` edge function — dual geographic matching (state + GPS radius ≤ 50 km)
- [x] `dispatch-webhook` edge function — notifies rider, customer, company on status changes
- [x] `notify-bid-placed` edge function — notifies customer when bid placed
- [x] `device_tokens` table — universal FCM token store
- [x] `fcm_service.dart` — saves token, handles tap routing
- [x] `auth_controller.dart` — FCM initializes for all logged-in users

#### GPS / Location Fixes
- [x] FK constraint bug fixed — `rider_locations.rider_id` FK pointed to wrong column
- [x] `rider_dashboard_page.dart` — `_withinRadius` state-first fallback to GPS
- [x] `rider_dashboard_page.dart` — `_stopLocationBroadcast` deletes stale `rider_locations` row
- [x] `delivery_tracking_page.dart` — clears rider pin immediately on `confirmed`
- [x] `rider_dashboard_page.dart` — `_confirmedPollTimer` 12s fallback poll for missed Realtime events

#### `pickup_state` + Geographic Matching
- [x] `pickup_state TEXT` column on `deliveries`
- [x] `LocationResult` extended with `state` field
- [x] `send_package_page.dart` captures and writes `pickup_state` on insert

#### Packages added to `pubspec.yaml`
- [x] `http: ^1.2.2`
- [x] `url_launcher: ^6.3.1`

---

### ZeeFashion ↔ Eziza Integration — COMPLETE (was "designed, not wired" — now fully live)

#### Full outsourcing model
- [x] `FeatureFlags.eziza` toggle (ZeeFashion admin → App Settings): when on, orders are fully outsourced — ZeeFashion's own internal riders/companies never see them, zero disruption to internal flow when toggled back off
- [x] `delivery_requests.routed_to` column (`internal` | `eziza`), decided client-side at creation from the flag (migration `20260705000000`)
- [x] Internal job boards (`rider_dashboard_page.dart`, `company_dashboard_page.dart` in ZeeFashion) filter on `routed_to = 'internal'`
- [x] `reject_bids_on_eziza_requests` trigger — defense-in-depth backstop against a client inserting an internal bid on an `eziza`-routed request by guessed ID

#### Buyer-facing Eziza bidding
- [x] `eziza_delivery_bids` table (isolated from internal `delivery_bids`) — migration `20260705010000`
- [x] `logistics-gateway` inbound `bid.placed` handler upserts into it, relayed from Eziza's `dispatch-bid-webhook`
- [x] `track_order.dart` shows/accepts/pays Eziza bids exactly like internal ones (wallet + Paystack)
- [x] `precheck_accept_eziza_bid` / `finalize_accept_eziza_bid` RPCs (migration `20260706000000`) — validates via caller's own JWT, calls Eziza's `accept-bid`, commits payment only after Eziza confirms, compensating `cancel-delivery` call on finalize failure

#### Live rider-location sharing with ZeeFashion
- [x] `eziza_rider/supabase/functions/dispatch-location-webhook` — DB webhook on `rider_locations` UPDATE, relays to tenant's `logistics-gateway`, looking up `riders.id` from `auth_user_id` first (see ID-system note below)
- [x] `delivery_requests.eziza_rider_lat/lng/eziza_rider_location_updated_at` columns (migration `20260707000000`, ZeeFashion side) — rides the same realtime channel already open for status, no new subscription needed
- [x] `delivery_map_page.dart` (ZeeFashion) — identical live map/polyline/ETA experience for Eziza-routed deliveries as internal ones, for both merchant and buyer
- [x] 2-minute staleness check on the relayed location — once a rider goes offline (their `rider_locations` row deleted), the relayed column doesn't sit there looking live forever
- [x] Map-consistency fixes: zoom-level parity with rider's own map (`_fitMap` only includes pickup pin during `to_pickup` phase), thicker/haloed polyline for visibility, rider marker + route cleared (not just left stale) once buyer confirms receipt

#### Handoff / receipt relay
- [x] Merchant "Confirm Handoff" (`store_order.dart`, `delivery_map_page.dart` isMerchant) → Eziza `confirm-pickup`, fire-and-forget
- [x] Buyer "Confirm Receipt" (`order_controller.dart::packageReceived`, `delivery_map_page.dart`) → Eziza `confirm-receipt`, fire-and-forget
- [x] New Eziza edge functions: `confirm-pickup`, `confirm-receipt`, `accept-bid`, `dispatch-bid-webhook`, `dispatch-location-webhook`

#### Notifications (see also Pending — one open issue below)
- [x] Ready-for-Pickup → matched riders/companies, both internal (`store_update_tracking.dart`) and Eziza (`notify-new-job` trigger on `deliveries` INSERT, coverage-state or 50km GPS match)
- [x] Bid placed → buyer, both internal individual-rider bids (already working), internal company bids (`company_dashboard_page.dart::_placeBid` — was missing, now fixed) and Eziza bids (`logistics-gateway`'s `bid.placed` handler — was missing, now fixed)
- [x] Bid accepted → winning rider/company, both sides (Eziza's `notify-bid-accepted` trigger is the single source of truth now — removed a broken/duplicate path in `dispatch-webhook` that queried a non-existent `is_accepted` column and used a legacy `fcm_token` field)
- [x] Rider arrival at pickup → merchant, both sides (Eziza: `awaiting_pickup_confirm` → `dispatch-webhook` → `logistics-gateway`'s `_notify`)
- [ ] **OPEN ISSUE:** despite all of the above being correctly wired in code (verified via audit + fixes), live testing reports notifications not firing at all. Needs a fresh device-level investigation — FCM delivery, `device_tokens` registration, or `send-notification` itself — not just the specific gaps already patched. (Tracked as a pending task in the ZeeFashion Claude Code session.)

#### Root-cause bugs found and fixed this round
- [x] JWT verification was blocking Eziza's tenant-facing endpoints — all 5 tenant functions redeployed `--no-verify-jwt`
- [x] `logistics-gateway` inbound handler silently broke ALL status-sync — selected a non-existent `rider_id` column on `delivery_requests` (real column is `assigned_rider_id`) and didn't check the error
- [x] `get-delivery` selected `lat, lng` instead of the real `latitude, longitude` columns on `rider_locations` — always returned `rider_location: null`
- [x] **Core ID-system bug:** `rider_locations.rider_id` is the rider's `auth.uid()` by design, but `deliveries.rider_id` is a different PK (`riders.id`) — `dispatch-location-webhook` and `get-delivery` compared them directly, so the location relay silently never matched an active delivery. Fixed by looking up `riders.auth_user_id` first in both places.
- [x] `track_order.dart::_pushDeliveryGps` was silently overwriting `delivery_requests.delivery_lat/lng` with the buyer's live phone GPS every time they opened the tracking screen, clobbering a merchant-resolved custom map-pin delivery address — now only seeds when the destination is still unresolved
- [x] Two more RLS subquery-reliability bugs, same class as the FK issue above: `deliveries_rider_select`'s `rider_id IN (subquery)` clause (migration `20260707100000` — denormalized to `rider_auth_user_id` direct column) and its company-visibility clause `id IN (SELECT _auth_company_bid_delivery_ids())` (migration `20260707180000` — denormalized to `bidder_company_auth_ids UUID[]` direct array-containment check). Supabase Realtime's `postgres_changes` authorization does not reliably evaluate subquery/function-wrapped RLS predicates — direct column comparisons are required. Symptom before the fix: riders never saw live rider-location updates for others' deliveries reliably, and companies saw deliveries stuck showing "open for bid" forever after being assigned elsewhere.
- [x] Individual rider dashboard: the open-job-board realtime channel had no UPDATE handler at all (only INSERT), so a delivery a rider bid on and lost had no code path to ever remove it from the list — added the missing handler
- [x] Individual rider dashboard: duplicate active-delivery card — two separate realtime channels (`deliveries` UPDATE and `delivery_bids` UPDATE→accepted) both insert into `_activeDeliveries` for the same bid-accepted transition; the second one checked "not already present" before an `await` and inserted unconditionally after, racing with the first channel's synchronous insert. Fixed with a re-check after the await.
- [x] `dropoff_lat`/`dropoff_lng` dead-column bug — four files (`rider_map_page.dart`, `company_map_page.dart`, `delivery_tracking_page.dart`, `send_package_page.dart`) read/wrote these instead of the real `delivery_lat`/`delivery_lng` columns, meaning riders/companies always fell back to re-geocoding the address text (or, for the company fleet map, skipped the dropoff pin entirely) instead of using the precise stored coordinate
- [x] `store_location_page.dart` (ZeeFashion, merchant's own store GPS) — GPS fetch had no timeout, could hang indefinitely on simulator making the "Update GPS Location" button look permanently disabled; added a 10s timeout with an explicit error (no silent last-known-location fallback, per explicit preference)
- [x] `delivery_map_page.dart` — "delivery confirmed" banner said "You confirmed receipt" to BOTH merchant and buyer regardless of who actually confirmed; now viewer-aware
- [x] `track_order.dart` — the map's own customised "Package Delivered" dialog and this page's simpler `SmartPopup` dialog could both fire and stack, since this page stays mounted underneath the pushed map page; now suppressed while the map is open, re-offered after it closes if still unconfirmed

#### New migrations this round (Eziza project)
- `20260706000000_dispatch_bid_webhook_trigger.sql`
- `20260707000000_dispatch_location_webhook_trigger.sql`
- `20260707100000_fix_deliveries_realtime_rls.sql` — `rider_auth_user_id` denormalization
- `20260707120000_fix_riders_vehicle_type_check.sql` — widened CHECK to 5 vehicle types the app actually offers
- `20260707170000_revert_rider_locations_own_policy.sql` — reverted an incorrect mid-investigation RLS change back to the original correct design
- `20260707180000_fix_company_bid_realtime_rls.sql` — `bidder_company_auth_ids` denormalization
- (Various numbered debug migrations between 20260706010000–20260707160000 were temporary diagnostics, applied and dropped in the same session — not meaningful history)

---

### Monetisation — Phase 1 (Foundation) COMPLETE

Before this, `riders.wallet_balance`/`companies.wallet_balance` were never written to anywhere (companies didn't even have the columns — `company_dashboard_page.dart` was reading them off a raw Map with a silent `?? 0.0` fallback), and `settings.platform_fee_pct`/`deliveries.platform_fee` existed but were never applied. Riders/companies would have kept 100% of every bid with zero commission taken.

- [x] Migration `20260707190000_monetisation_foundation.sql`:
  - Added `deliveries.delivery_fee_breakdown JSONB`
  - Added `companies.wallet_balance`/`total_earned`/`paid_out` (didn't exist at all — real gap, not just unused)
  - New `earnings_ledger` table — itemized, auditable record of every delivery's gross/commission/net split, RLS-scoped per rider/company
  - `credit_delivery_earnings()` trigger, fires once per delivery on the `-> confirmed` transition: reads `platform_fee_pct` from `settings`, computes commission + net, writes the fee breakdown back onto the delivery, inserts one `earnings_ledger` row, and credits the winning party's `wallet_balance` — the winning party is whoever's bid was `accepted` (a company, if a company won, even though it may internally assign one of its own riders to actually do the job — that rider isn't paid directly through the platform)
  - One-time backfill for pre-existing `confirmed` deliveries in the same migration (verified against 10 real historical deliveries — commission math checked out on both the individual-rider and company-won paths)
- [x] `company_dashboard_page.dart` — added a "Recent Earnings" itemized section to the Earnings tab (`_earningsHistoryCard`), same gross/commission/net breakdown pattern the rider's `earnings_page.dart` already had (that page needed zero changes — it already read `platform_fee`/`agreed_price` directly, just had nothing populating them until now)
- [x] **Live-verified 2026-07-09**: real bug found in the process — `credit_delivery_earnings()` wasn't `SECURITY DEFINER`, so its writes to `earnings_ledger`/`riders`/`companies` ran under the *confirming user's own* RLS grants and were silently rejected (no INSERT policy on `earnings_ledger` at all), rolling back the whole delivery confirmation. Fixed + backfilled. Full flow now confirmed working end-to-end through the real app.

### Monetisation — Phases 2+ (not started)
- [ ] Markup on external carrier quotes — blocked on Shipbubble integration (deferred)
- [ ] Admin earnings dashboard — blocked on `eziza-admin` (no admin panel exists yet at all)
- [ ] Tenant billing ledger — no real invoicing/payment-collection mechanism from tenants exists yet; likely just a reporting view over `earnings_ledger` grouped by tenant until then

### Multi-party delivery ratings — COMPLETE, live-verified 2026-07-09
Replaced the old unused `delivery_ratings` (single rider/customer rating pair) with a checkpoint-based model covering all 4 directions: sender↔rider at handoff, receiver↔rider at delivery. `riders.rating_count` added (didn't exist, unlike `companies`). Each rating snapshots `rater_name` so a company can trace a bad rating on one of their riders back to the specific customer — `CompanyRiderRatingsPage`, opened by tapping a rider in the My Riders tab, lists this per rider.
- [x] Migration `20260707250000_multi_party_ratings.sql` — new schema, `credit_rider_rating()` aggregation trigger, RLS (insert scoped to your actual role on the delivery; select scoped to your own ratings, ratings about you, or — for companies — ratings about riders linked via `company_rider_invites`)
- [x] `lib/widgets/rating_sheet.dart` + `lib/services/ratings_service.dart` — shared skippable 5-star sheet + submit/already-rated-check helpers
- [x] Wired into `customer_delivery_detail_page.dart`, `delivery_tracking_page.dart` (both live, both need it independently), `rider_map_page.dart`
- [x] Decoupled from status-transition ordering — manual "Rate Rider"/"Rate Sender"/"Rate Receiver" entry points added (assigned-rider card, live-tracking card, rider map's top-bar "Rate" menu) so any party can rate any time, not just right after a specific confirm action
- [x] `credit_rider_rating()` also needed `SECURITY DEFINER` (same bug class as the earnings trigger) — fixed + backfilled
- [x] Companies are now also credited from their riders' ratings (`companies.rating_avg/rating_count`), with a full reviews list (rater, role, stars, comment, which rider) on both the company's own Rating tab and the individual rider's Rating tab
- [x] Live-verified end-to-end through the real app, including company-employed rider flow

---

## 🚧 Pending / Not Yet Tested

### Immediate — Test These First
- [ ] **OTP flow end-to-end** — rider marks delivered → OTP sheet shows → enter code → delivery confirmed → map closes
- [ ] **Dev OTP fallback** — when Termii rejects key, amber banner shows code; enter it manually
- [ ] **Termii API key** — awaiting support reply; once fixed, remove dev_otp fallback test
- [ ] **Recipient phone-match** — register with phone, sender puts same number as contact → delivery appears in Incoming tab automatically
- [ ] **Tracking code claim** — sender taps code in header, copies it → recipient enters in "Find Package" sheet → auto-claimed → appears in Incoming tab → "View & Track Delivery" opens detail page
- [ ] **Recipient live tracking** — tap "Track Live" from incoming card → sees same map as sender, no handoff button
- [ ] **Recipient confirm receipt** — tap "Confirm Receipt" from incoming card/detail → delivery confirmed → rider map closes

### Infrastructure
- [ ] **iOS APNs key** — upload APNs Auth Key to Firebase Console (manual step)
- [ ] **Custom domain for API** — replace raw Supabase URL with `api.eziza.com`
- [ ] **Admin dashboard** — approve riders/companies, manage `locations`, view all deliveries, manage payouts

### ZeeFashion ↔ Eziza Integration — now complete, see the dedicated section above
- [ ] **Notifications reported as not firing at all** in latest live testing, despite the notification wiring for all 4 key events (ready-for-pickup, bid placed, bid accepted, rider arrival) being verified correct in code on both the internal and Eziza paths. Needs device-level debugging next: confirm `device_tokens`/FCM token registration actually happened for the test accounts, check `send-notification`'s logs for the actual FCM API response (not just that it was invoked), and check the Firebase project's APNs/FCM config is still valid. Do not assume the earlier code fixes are wrong until this is isolated — they closed real gaps, but something upstream (or the test device's token) is likely still broken.
- [x] Pass buyer phone number when ZeeFashion creates Eziza delivery — `store_update_tracking.dart` forwards both `pickup_contact_phone` and `delivery_contact_phone` through `logistics-gateway` to Eziza's `create-delivery`
- [x] Wire ZeeFashion merchant handoff confirm → Eziza `picked_up`
- [x] Extend `dispatch-webhook` — on `delivered`, fire tenant webhook so buyer sees confirm prompt
- [x] ZeeFashion `packageReceived()` calls back to Eziza → `confirmed`

### External Carriers / Shipbubble
- [ ] `external_carriers` + `external_carrier_rates` + `external_carrier_bookings` DB migration
- [ ] Shipbubble API integration — live quotes alongside rider bids
- [ ] Admin panel — manage carriers + manual rate cards
- [ ] Customer delivery detail page — "External Carriers" section
- [ ] Booking flow + tracking poll

### Monetisation
- [ ] Commission deduction in `pay_and_accept_delivery_bid` RPC
- [ ] Markup on external carrier quotes
- [ ] `delivery_fee_breakdown` jsonb column on `deliveries`
- [ ] Admin earnings dashboard
- [ ] Tenant billing ledger

---

## 🗺️ Roadmap — Phases 1-6

### Phase 1 — Monetisation Foundation — COMPLETE, live-verified 2026-07-09
Full design + schema is documented above under "Monetisation — Phase 1 (Foundation) COMPLETE" — `earnings_ledger` table, `credit_delivery_earnings()` trigger (fires on `-> confirmed`, incremental-crediting pattern matching ZeeFashion's `wallet_transaction` trigger — nothing else should ever directly `UPDATE riders/companies SET wallet_balance = ...`), backfill for pre-existing confirmed deliveries, itemized history on `earnings_page.dart`. Verification checklist (manual status flip, idempotency check, both individual-rider and company-won paths, itemized history render) — all passed. The one real bug found along the way (missing `SECURITY DEFINER`, silently blocking the trigger's writes for any non-service-role confirming user) is documented in that section too.

### Phase 2 — eziza-admin — BUILT + live-verified 2026-07-10
New repo at `/Users/zionnite/StudioProjects/eziza-admin` (sibling to `eziza_rider`, own git repo, no remote yet), structurally mirrors `zeefashion-admin` (App Router, `admin_profiles` table + `is_active` flag for auth gating, `Sidebar.tsx` nav pattern) — but does **not** copy zeefashion-admin's one real flaw: `lib/supabaseBrowser.ts` (anon key) and `lib/supabaseAdmin.ts` (service-role, guarded by the `server-only` package) are split, and every privileged read/write goes through `/api/admin/*` Route Handlers authenticated by `lib/adminAuth.ts::requireAdmin()` (verifies the caller's own access token, then checks `admin_profiles.is_active`). Verified empirically that the service-role key does not appear anywhere in the built `.next` output (client or server bundles) — Next.js reads non-`NEXT_PUBLIC_` env vars from `process.env` at runtime, never inlines them.

- [x] Migration `20260710020000_admin_profiles.sql` — table + self-select-only RLS policy (every other operation is server-side)
- [x] **Approvals** (`/dashboard/approvals`) — riders/companies tabs, pending-first sort, approve/reject/suspend/reinstate, push notification on status change (`device_tokens` lookup by `auth_user_id` + `send-notification` edge function — Eziza has no `send-email` function yet, so email-on-status-change from the original ZeeFashion pattern is not implemented here)
- [x] **Deliveries** (`/dashboard/deliveries`) — all tenants, status filter chips
- [x] **Earnings** (`/dashboard/earnings`) — `earnings_ledger` itemized list (payee via FK embed to `riders`/`companies`) + aggregate gross/commission/net cards
- [x] **Tenant Billing** (`/dashboard/billing`) — commission grouped by `deliveries.tenant_id` (aggregated server-side in the Route Handler, since `earnings_ledger` has no `tenant_id` column of its own); explicitly reporting-only, no invoicing/collection
- [x] **Settings** (`/dashboard/settings`) — `platform_fee_pct` editor (stored as a 0-1 fraction in `settings`, edited as a 0-100 percentage in the UI)
- [x] **Support** (`/dashboard/support`) — placeholder page, real UI waits on Phase 6's ticket schema
- [x] **Users** (`/dashboard/users`) — senders/receivers, who have zero DB presence otherwise (no `customers` table until Phase 3). Sourced by exclusion: every `auth.users` row that isn't a rider/company/admin, enriched with `full_name`/`phone` from `user_metadata` (set at signup by `register-user`) and delivery activity (count + total spent from `deliveries.customer_id`). Live-verified: correctly found 2 real customers with real delivery/spend numbers, correctly excluded the 5 riders + 1 company + admin account.
- [x] `npm run build` and `npm run lint` both clean (one new stricter lint rule, `react-hooks/set-state-in-effect`, flags the standard "fetch on mount" `useEffect(() => { load() }, [dep])` pattern used throughout this app and its ZeeFashion sibling — downgraded to a warning in `eslint.config.mjs` rather than restructured)
- [x] First admin created: `admin@eziza.online` (dedicated admin account, not reused from any rider/company/customer signup) — new `auth.users` row + `admin_profiles` row with `is_active=true`
- [x] **Live-verified 2026-07-10**: real login → real access token → every `/api/admin/*` route hit with it and returned correct live data (5 riders, 90 `earnings_ledger` rows, billing correctly split ₦39,823.80 commission for Eziza Direct vs ₦3,638 for ZeeFashion, settings returned `platform_fee_pct: 0.10`); confirmed the same request without a token gets 401
- [ ] Not deployed anywhere yet (local only — `npm run dev` on the developer's machine)

### Phase 3 — Customer Wallet — BUILT + live-verified 2026-07-10

**Scope grew beyond the original bullet list**: deliveries had zero payment step at all before this — accepting a bid just set `status='assigned'` with nothing ever collected from the customer, while `credit_delivery_earnings()` still credited the winning rider/company. Discovered mid-phase, confirmed with the user, and wired the wallet in as the actual payment method for accepting a bid (not just a top-up/balance feature sitting unused).

**Security deviation from the original plan (deliberate, checked directly against source):** the original bullet said to use the `pay_with_paystack` package "mirroring ZeeFashion's `wallet.dart`". Reading `pay_with_paystack`'s actual source (`~/.pub-cache/hosted/pub.dev/pay_with_paystack-1.0.10/lib/src/paystack_pay_now.dart`) shows it calls `api.paystack.co` directly from the client with `Authorization: Bearer <secretKey>` — and ZeeFashion's `wallet.dart`/`check_out_payment.dart`/`subscription_plans_page.dart` all fetch that real secret key client-side via the `paystack-key` edge function (`sec_key` in the response) and pass it straight into the package. **This means ZeeFashion is currently shipping its live Paystack secret key to every authenticated client** — same class of issue as `zeefashion-admin`'s `NEXT_PUBLIC_SUPABASE_SERVICE_ROLE_KEY`, just in the mobile app instead of the admin panel. Flagging this here since it's a real, separate, already-shipped vulnerability — not touched as part of this phase (different codebase/session), but should be fixed. Eziza does **not** use `pay_with_paystack` — see below for what it does instead.

- [x] Migration `20260711000000_customers_table.sql` — `customers` table (`id, full_name, phone, avatar_url, wallet_balance, created_at`), auto-created for every `auth.users` insert via a trigger, backfilled for existing users (riders/companies/admin included — anyone can be a sender)
- [x] Migration `20260711010000_wallet_transactions.sql` — ledger + `credit_wallet_transaction()` trigger (`SECURITY DEFINER` from the start this time, learning from the earlier `credit_delivery_earnings()`/`credit_rider_rating()`/`sync_deliveries_bidder_company_auth_ids()` bugs — all three were missing it and silently failed under the acting user's own RLS). Types: `credit`/`debit`/`refunded`. Unique index on `reference` (where not null) for idempotency against Paystack's webhook retries.
- [x] Migration `20260711020000_deliveries_payment_columns.sql` — `payment_source`/`payment_ref`/`payment_status` (default `'unpaid'`)
- [x] Migration `20260711030000_pay_and_accept_delivery_bid.sql` — atomic RPC: verifies caller, checks balance, debits, accepts the bid + rejects the others, marks the delivery paid. `RAISE EXCEPTION 'Insufficient wallet balance'` on shortfall (caught client-side, shown as a dialog linking to the wallet page)
- [x] Migration `20260711040000_cancel_delivery_with_refund.sql` — same cancellable scope as the existing `cancel-delivery` edge function (`open`/`assigned`); refunds the wallet if the delivery was paid
- [x] Edge function `paystack-webhook` — verifies Paystack's HMAC-SHA512 signature, credits the wallet on `charge.success`, idempotent via the reference unique index
- [x] Edge function `paystack-initialize` — the only thing that touches `PAYSTACK_SECRET_KEY`; verifies the caller's own JWT and that `customer_id` matches before calling Paystack's `/transaction/initialize`
- [x] Edge function `paystack-public-key` — serves the public key to the app at runtime (no auth needed — public keys are meant to be client-side), so it can rotate without an app release
- [x] `lib/services/wallet_service.dart` + `lib/pages/customer/wallet_page.dart` (balance hero, top-up sheet with quick-amount chips, transaction history) — new "Wallet" tile in the customer Account tab
- [x] `customer_delivery_detail_page.dart::_acceptBid()` now calls `pay_and_accept_delivery_bid` instead of an unconditional status update; insufficient balance shows a dialog linking to the wallet page
- [x] New "Cancel Delivery" action (open/assigned only) with a refund-aware confirmation dialog, calling `cancel_delivery_with_refund`
- [x] **Live-verified 2026-07-10** via real RPC calls under an actual customer JWT (not service role): insufficient-balance correctly rejected → credited wallet 1000 → bid-accept correctly debited 500, set `status='assigned'`, `payment_status='paid'`, `agreed_price`, `rider_id` → cancel correctly refunded 500 → final ledger exactly right (credit 1000 → debit 500 → refund 500 → balance back to 1000). Test data cleaned up afterward.

**Top-up checkout UX — went through 3 iterations, all live-tested against real payments:**
1. First attempt: `url_launcher`'s `LaunchMode.inAppBrowserView` (external SFSafariViewController/Custom Tabs) with `callback_url` set to a raw `eziza://wallet-topup-complete` scheme. **Failed live** — Paystack's API silently ignores a non-http(s) `callback_url`; the checkout just stayed on its own "Payment Successful" page with zero navigation attempted.
2. Second attempt: added `paystack-return`, a real `https://` bridge page (Paystack redirects here fine) that tried to auto-redirect to the custom scheme via `<meta refresh>` + JS. **Failed live twice** — first, iOS Safari deliberately blocks non-user-gesture navigation to unrecognized URL schemes (a real WebKit restriction, not a bug), so it just sat on the bridge page; then, the instant (`content="0"`) meta-refresh raced the page's initial paint and the WebView rendered raw HTML source as plain text instead of the page. Stripped the auto-redirect entirely, left a plain tappable "Return to Eziza" button — this worked, but still needed a manual tap.
3. **Final architecture**: realized the reason `zeefashion`'s `pay_with_paystack`-based flows feel automatic isn't an OS-level trick at all — that package renders checkout in an embedded `webview_flutter` WebView inside the app and its own Dart code watches navigation to auto-close, which is a completely different (and better) mechanism than an external browser + custom scheme. Built the same thing directly: new `lib/pages/customer/paystack_checkout_page.dart` loads the `authorization_url` in an embedded `WebViewWidget`, whose `NavigationDelegate.onNavigationRequest` detects navigation to the `paystack-return` URL and pops the page immediately — no scheme handoff, no button tap, no OS permission dialog. Kept the `eziza://` deep-link/`AppLinks` wiring from attempt 2 as a defensive fallback only. **Deliberately does not use `pay_with_paystack` itself** — see the security note above; the WebView-auto-close technique and the secret-key exposure are separable, and only the former was worth copying.
- [x] **Webhook registered and confirmed working 2026-07-08**: 8 real top-ups (₦1,000–₦15,000, ₦35,000 total) credited correctly and automatically after registration, including a full live test of the final embedded-WebView checkout page — auto-closed back into the app with no manual tap, balance refreshed immediately. Phase 3's payment flow is fully live-verified end-to-end now, not just at the RPC level.
- [ ] **Two ₦10,000 top-ups from before the webhook was registered are still uncredited** (`topup_a8612a04_1783495293774`, `topup_a8612a04_1783495222949` — found via the admin-only `paystack-list-recent` function, predate registration, Paystack's retry window has likely passed). Deliberately **not credited** — pending the user confirming these payments are actually theirs, since crediting a wallet is real money movement.

### Phase 4 — Security (customer-only) — BUILT 2026-07-12

**Cross-cutting security fix found and applied first (2026-07-12), not specific to Phase 4:** while adding the `customers` UPDATE policy needed for the PIN feature, discovered that Supabase's default privileges grant `authenticated` a blanket table-level UPDATE (all columns) on every table, which silently coexists with any RLS UPDATE policy scoping to "own row." A column-scoped `GRANT` alone does nothing — `GRANT` is purely additive and never narrows a broader existing grant; `REVOKE` is required first. Confirmed empirically (throwaway test rider account) that riders/companies could directly PATCH their own `wallet_balance`, `rating_avg`/`rating_count`, and `is_approved`/`status` — bypassing the admin-approval flow (Phase 2's whole reason for existing) and every rating/earnings trigger — and that a customer could tamper with `deliveries.agreed_price`/`platform_fee`/`payment_status` the same way.

- [x] Migration `20260712000000_customer_pin.sql` — `customers.pin`/`pin_set` (boolean, not ZeeFashion's TEXT 'yes' flag — cleaner typing, same plaintext-PIN behavior) + the `customers` UPDATE policy/grant fix
- [x] Migration `20260712070000_lock_down_sensitive_columns.sql` — same fix applied to `riders` (allowlist: profile fields, `is_available`, `fcm_token`, application docs — mapped from every real `from('riders').update()` call site in the app), `companies` (blanket revoke, nothing re-granted — no app code updates a company row post-registration at all yet), `deliveries` (blocklist — just the financial columns, since this table's legitimate direct-write surface is large and already correctly scoped by existing RLS)
- [x] Live-verified: legitimate writes (rider toggling `is_available`, `pay_and_accept_delivery_bid` setting `agreed_price`/`payment_status` via its `SECURITY DEFINER` context) still work; all tested tampering attempts (wallet_balance, self-approval, rating inflation) correctly rejected with 403, rows confirmed unchanged
- [x] Confirmed zero impact on the ZeeFashion/tenant integration — every tenant-facing edge function uses the service-role key exclusively, which bypasses RLS and every GRANT/REVOKE restriction
- [ ] **Worth checking in ZeeFashion's own Supabase project too** — this is a Supabase-platform-wide default-privilege behavior, not something specific to how Eziza's schema was set up, so the same gap plausibly exists there (`profiles.current_balance`, etc.). Not investigated — separate live app, out of scope here. See [[project_zeefashion_paystack_security]] memory.

**PIN/biometric feature itself — BUILT 2026-07-12, not yet live-verified in the app UI:**
- [x] `local_auth`/`local_auth_android`/`local_auth_darwin`/`flutter_otp_text_field`/`shared_preferences` added to `pubspec.yaml`
- [x] `lib/services/local_auth_services.dart` — same `LocalAuth.authenticate()` wrapper as ZeeFashion
- [x] `lib/widgets/pin_verification_sheet.dart` — reads `customers.pin` directly and compares (simpler than an RPC — matches ZeeFashion's own working fallback path), shows a biometric shortcut when `fingerprintAuth` is on
- [x] `lib/pages/customer/change_transaction_pin.dart` → `verify_transaction_pin.dart` — 2-step set-PIN flow (`OtpTextField`), final save writes `customers.pin`/`pin_set` directly, protected by the column-grant fix above
- [x] `lib/pages/customer/security_page.dart` — new "Security" tile in the Account tab: Change Transaction PIN + biometric toggle
- [x] `customer_delivery_detail_page.dart::_acceptBid()` — checks `pin_set` first (prompts to set one if missing, matching ZeeFashion's exact messaging), gates payment behind `PinVerificationSheet.verify()` before calling `pay_and_accept_delivery_bid` — same wiring point ZeeFashion uses in `track_order.dart`
- [x] `flutter analyze` clean across the whole `lib/` tree
- [ ] Not yet run through the actual Flutter app UI — only the DB layer (column grants, `customers.pin`/`pin_set` writes) has been live-verified so far

### Phase 5 — Change Password, Profile, Bank Account (all 3 roles) — BUILT 2026-07-13

**Scope discovery before building**: riders already had a complete, working `ProfilePage` (personal info + vehicle + bank details, all wired to a real `updateProfile` call) — Phase 5 for riders turned out to just be "add a photo," not a rebuild. Companies had genuinely zero edit capability of any kind, matching the roadmap's note exactly.

- [x] `lib/pages/shared/change_password_page.dart` — one shared page for all 3 roles, replacing 2 duplicated bottom sheets (customer, rider) and adding the missing company path. Mirrors ZeeFashion's `change_password.dart` exactly, including "current password" being collected/validated as non-empty but never actually verified against the account (`auth.updateUser()` doesn't require it) — matched intentionally per the roadmap's note.
- [x] `lib/pages/customer/edit_profile_page.dart` — replaces the old ad-hoc bottom sheet, which only ever wrote to `auth.user_metadata` and never the `customers` table (a real gap since Phase 3 — anything reading `customers.full_name`/`phone` was stale after an edit). Now writes to `customers` as the source of truth, keeps auth metadata in sync for other read sites. Photo upload added.
- [x] `lib/pages/home/profile_page.dart` (rider) — added avatar upload to the existing page rather than rebuilding it; added `Rider.avatarUrl` to the model.
- [x] `lib/pages/home/company_profile_page.dart` — new, company's first-ever post-registration edit page: hero header with status badge, Company Info, Location, Bank Details (reuses the same `BankService` bank picker as registration, so `bank_code` is captured correctly for payouts — not just free-text like rider's page), photo upload. Wired "Edit Profile" + "Change Password" tiles into the Account tab for the first time.
- [x] **Photo upload uses Eziza's own Bunny CDN zone** (`lib/services/bunny_service.dart`, `eziza.b-cdn.net`, already used for rider docs at `rider-docs/<uid>/...`) — **correction 2026-07-13**: briefly built a Supabase Storage bucket + RLS policies for this before realizing Eziza already had its own Bunny zone (an earlier note in this doc wrongly said it didn't); reverted that (migration `20260713010000`) in favor of `BunnyService.upload()`.
- [x] Migration `20260713020000` — `avatar_url` on `riders`/`companies`, and `companies`' first-ever column-level UPDATE grant (previously zero — nothing could update a company row post-registration at all)
- [x] **Bank Account**: ended up as its own clearly-labeled section within each role's profile page (matching how it already worked for riders) rather than a fully separate page — same practical effect, one less page to navigate through
- [x] `flutter analyze` clean across the whole `lib/` tree
- [x] **Live-verified 2026-07-13** with throwaway test accounts: full company field set (name/contact_person/phone/cac_number/state/city/bank_name/bank_code/account_number/account_name/avatar_url) updates correctly in one request; `wallet_balance`/`is_approved`/`status` confirmed untouched by the same request
- [ ] Not yet clicked through in the actual app UI (photo picker, bank dropdown, save flows for all 3 roles) — only the DB-layer writes are live-verified

Phase 6 below was scoped out in full but not started as of 2026-07-10. It deliberately mirrors an existing ZeeFashion pattern rather than inventing a new one.

### Phase 6 — Support Tickets (all 3 roles + admin reply)
- New migration porting ZeeFashion's `support_tickets`/`support_messages` schema near-verbatim (including the undocumented-but-live `support_messages.image_url` column), adapted to reference `auth.users` directly (Eziza has no unified `profiles` table)
- Flutter: `support_tickets_page.dart`/`create_ticket_page.dart`/`ticket_thread_page.dart` ported per ZeeFashion's structure, wired into all 3 roles' "Help & Support" tiles (replacing the current WhatsApp/"Coming Soon" stub)
- Image attachments via `BunnyService.upload()`, same as Phase 5's avatars
- Admin reply UI in eziza-admin mirrors ZeeFashion admin's two-pane list+thread+realtime page

**Note:** the notification bug in the Pending section above is a separate track from these phases — it's a live bug in already-shipped Phase 1 functionality, not new scope. Worth fixing before or alongside Phase 2, since an admin dashboard doesn't help if the underlying app can't notify anyone.

---

## Key Credentials & URLs

| Item | Value |
|---|---|
| Eziza Supabase project | `nvwpsccleewgirlwokys.supabase.co` |
| Eziza DB pooler | `postgresql://postgres.nvwpsccleewgirlwokys:V3JYMT0xTUTUosKM@aws-0-eu-west-1.pooler.supabase.com:5432/postgres` |
| Eziza GitHub | `https://github.com/zionnite/eziza.git` |
| Termii SMS | Key pending (support ticket open — both `tlv_Hn4r...` and `tlv_VdZ-...` rejected 401) |

## Tracking Code Format
- 6 uppercase alphanumeric chars
- Character set: `ABCDEFGHJKMNPQRSTUVWXYZ23456789` (no O, 0, I, 1, L)
- ~1 billion possible codes — no collisions at any realistic scale
- Sender taps code in delivery header to copy → shares via WhatsApp/SMS
- Recipient enters code in "Track a Package" → auto-claimed in one step, no confirm button
