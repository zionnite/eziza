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

## 🗺️ Roadmap — Phases 2-6 (designed, not built)

Phase 1 (rider/company/customer core app, monetisation foundation, multi-party ratings) is complete and live-verified above. The phases below were scoped out in full but not started as of 2026-07-09. Each deliberately mirrors an existing ZeeFashion admin/Flutter pattern (same tables, same file structure) rather than inventing new conventions, except where explicitly called out.

### Phase 2 — eziza-admin (new standalone Next.js app)
New repo/directory, structurally mirrors `zeefashion-admin` (App Router, client-side Supabase calls, `admin_profiles` table + `is_active` flag for auth gating, `Sidebar.tsx` nav pattern) — but does **not** copy zeefashion-admin's one real flaw: the service-role key stays server-only (Route Handlers/Server Actions), never shipped to the browser under `NEXT_PUBLIC_`.

Sections:
- **Riders/Companies approval queues** — direct template: ZeeFashion admin's `logistics/page.tsx` pending-first-section + approve/reject/suspend pattern with push+email on status change
- **Deliveries**
- **Earnings** — reads `earnings_ledger` + `tenants`, aggregate commission over time/per-tenant (the "admin earnings dashboard" backlog item)
- **Tenant Billing** — summary view over `earnings_ledger` grouped by tenant/period; real invoicing/collection out of scope until there's an actual payment-collection mechanism from tenants
- **Settings** — `platform_fee_pct` editor
- **Support** — ticket reply UI, built alongside Phase 6's ticket schema

### Phase 3 — Customer Wallet
New `customers` table — customers currently have zero DB row (identity lives only in `auth.users` metadata); this table becomes the home for `wallet_balance` and later Phase 4's `pin`/`pin_set` and an avatar URL:
`id UUID PK REFERENCES auth.users(id), full_name, phone, avatar_url, wallet_balance NUMERIC DEFAULT 0, created_at`

- New `wallet_transactions` ledger + credit/debit trigger, mirroring ZeeFashion's `wallet_transaction` type-set pattern (credit/debit/refunded at minimum)
- New Eziza `paystack-webhook` edge function (Eziza's own Paystack keys, already in hand) for `charge.success` → credit
- New `wallet_page.dart` mirroring ZeeFashion's `wallet.dart` (hero balance, top-up sheet via `pay_with_paystack` package — needs adding to `pubspec.yaml`, transaction list)
- Refund path: cancelling a paid delivery inserts a `type='refunded'` row

### Phase 4 — Security (customer-only)
- Add `local_auth` to `pubspec.yaml`
- 2-step PIN flow (`change_transaction_pin.dart` → `verify_transaction_pin.dart`, `OtpTextField`) writing to `customers.pin`/`pin_set` — matches ZeeFashion's exact **plaintext-storage pattern unless told otherwise**
- `pin_verification_sheet.dart` equivalent wired into wallet-spend actions
- Biometric toggle via `SharedPreferences['fingerprintAuth']` + a `local_auth_services.dart` wrapper — mirrors ZeeFashion's implementation directly

### Phase 5 — Change Password, Profile, Bank Account (all 3 roles)
- **Change Password**: one shared page matching ZeeFashion's `change_password.dart` exactly (current/new/confirm fields, same non-verification-of-current-password behavior, same `auth.updateUser` call) — wired into all 3 dashboards' Account tabs, replacing rider/customer's ad-hoc bottom sheets and adding the missing company path
- **Profile**: rebuilt per role matching `profile_page.dart` (display) + `edit_profile.dart` (edit). Photo upload uses **Supabase Storage, not Bunny CDN** — Eziza has no Bunny account of its own; using ZeeFashion's would upload into the wrong brand's storage. Company gets its first-ever post-registration edit capability (`companies` table currently only ever gets inserted, never updated)
- **Bank Account**: split out of Profile into its own page/section for rider and company (currently embedded in rider's profile form; never editable at all for company post-registration)

### Phase 6 — Support Tickets (all 3 roles + admin reply)
- New migration porting ZeeFashion's `support_tickets`/`support_messages` schema near-verbatim (including the undocumented-but-live `support_messages.image_url` column), adapted to reference `auth.users` directly (Eziza has no unified `profiles` table)
- Flutter: `support_tickets_page.dart`/`create_ticket_page.dart`/`ticket_thread_page.dart` ported per ZeeFashion's structure, wired into all 3 roles' "Help & Support" tiles (replacing the current WhatsApp/"Coming Soon" stub)
- Image attachments via Supabase Storage (same reasoning as Phase 5, not Bunny)
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
