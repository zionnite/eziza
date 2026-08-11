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

#### Subscription plans — companies + tenants (design discussion 2026-07-16, not started)
Goal, per the user: give companies a real reason to go all-in on Eziza, and make tenant revenue actually collectible (currently just a reporting view, nothing invoices/collects). **Subscription is additive — it does NOT replace or discount the existing per-delivery `platform_fee_pct` commission.** It's a separate recurring charge that unlocks features/capacity; no interaction with the commission math to design.

- [ ] **Companies** — tiered plans, same pattern as ZeeFashion's existing `subscription_plans` (starter/basic/standard/premium, manual admin overrides). Candidate gated features, strongest first:
  - Fleet seat cap — free tier caps riders-per-company, paid tiers raise/remove it. Primary lever: fleet size directly limits how much delivery volume a company can take on, so this is the one that makes paying feel like "I can do more business," not just a badge.
  - Priority job visibility — paid companies see/bid on open deliveries before free-tier ones, or get an exclusive early window on high-value jobs.
  - Analytics — per-rider performance, delivery volume trends, earnings breakdown (mostly reads off tables that already exist).
  - Multiple admin logins per company account (currently one login per company).
  - Support SLA — faster ticket response, reusing the Phase 6 support ticket system.
  - Anchor features to lead with: fleet seat cap + priority job visibility.
- [ ] **Tenants** — frame as volume-banded usage billing, not a consumer subscription: monthly committed-delivery-volume bands, each with a flat platform-access fee (stacked on top of the unchanged per-delivery commission) that buys things like webhook retry SLA, a staging API key, dedicated support channel. This is really "finally build the invoicing/collection layer" on top of the billing report that already exists in `eziza-admin` — same underlying gap as "Tenant billing ledger" above.
- [ ] **Riders** — explicitly deferred, not planned for now. Riders are the scarce supply side early on; a mandatory subscription to participate would shrink supply right when it's needed most. If ever built, must be optional and tied to a real perk (lower commission %, priority job visibility) — never a paywall to use the app.

Recommended sequencing: tenant billing/collection first (highest leverage, gap already flagged above, ZeeFashion revenue sitting uncollected) → company tiers second (seat cap + priority visibility as anchor) → riders not now.

### Multi-party delivery ratings — COMPLETE, live-verified 2026-07-09
Replaced the old unused `delivery_ratings` (single rider/customer rating pair) with a checkpoint-based model covering all 4 directions: sender↔rider at handoff, receiver↔rider at delivery. `riders.rating_count` added (didn't exist, unlike `companies`). Each rating snapshots `rater_name` so a company can trace a bad rating on one of their riders back to the specific customer — `CompanyRiderRatingsPage`, opened by tapping a rider in the My Riders tab, lists this per rider.
- [x] Migration `20260707250000_multi_party_ratings.sql` — new schema, `credit_rider_rating()` aggregation trigger, RLS (insert scoped to your actual role on the delivery; select scoped to your own ratings, ratings about you, or — for companies — ratings about riders linked via `company_rider_invites`)
- [x] `lib/widgets/rating_sheet.dart` + `lib/services/ratings_service.dart` — shared skippable 5-star sheet + submit/already-rated-check helpers
- [x] Wired into `customer_delivery_detail_page.dart`, `delivery_tracking_page.dart` (both live, both need it independently), `rider_map_page.dart`
- [x] Decoupled from status-transition ordering — manual "Rate Rider"/"Rate Sender"/"Rate Receiver" entry points added (assigned-rider card, live-tracking card, rider map's top-bar "Rate" menu) so any party can rate any time, not just right after a specific confirm action
- [x] `credit_rider_rating()` also needed `SECURITY DEFINER` (same bug class as the earnings trigger) — fixed + backfilled
- [x] Companies are now also credited from their riders' ratings (`companies.rating_avg/rating_count`), with a full reviews list (rater, role, stars, comment, which rider) on both the company's own Rating tab and the individual rider's Rating tab
- [x] Live-verified end-to-end through the real app, including company-employed rider flow

### Public bidder ratings for customers — BUILT + live-verified 2026-07-18
Before this, a customer choosing between offers on a delivery had no way to see the bidding rider's/company's reputation or photo — `delivery_ratings`' RLS only let the rater, the ratee, or the ratee's employing company read a rating row, and the bid query never selected `avatar_url` at all.
- [x] Migration `20260718000000_public_ratings_rpc.sql` — `get_public_ratings(p_ratee_type, p_ratee_id)` SECURITY DEFINER RPC, granted to `authenticated`. Deliberately narrower than just opening up the raw table: anonymised (no `rater_name`/`rater_auth_id`), rider ratings only (a company's reputation is always derived from its fleet, same `company_rider_invites`-joined query `credit_rider_rating()`/the 2026-07-09 backfill already use — there's no such thing as a `ratee_role='company'` row).
- [x] `customer_delivery_detail_page.dart` — bid queries (`_load()` and the realtime insert handler) now select `avatar_url`/`rating_count` alongside the existing `rating_avg` for both `rider` and `company`. `_bidCard`'s avatar circle shows the real photo (`CachedNetworkImageProvider`) when uploaded, falling back to initials otherwise. The avatar + name + rating block is now a `GestureDetector` opening the new `PublicRatingsPage`.
- [x] `lib/pages/customer/public_ratings_page.dart` — new page: aggregate rating header (passed in from the bid card, no extra round-trip) + a live-fetched anonymised review list via `get_public_ratings`. Same `PremiumCard`/`StatusPill` visual language as `CompanyRiderRatingsPage`, just without rater attribution.
- [x] `flutter analyze` clean across the whole `lib/` tree
- [x] **Live-verified 2026-07-18**: RPC called directly against a real rider with existing ratings returns the correct anonymised rows (200, no rater identity fields); called again as a throwaway customer account with zero relationship to that rider — same correct result (200); confirmed the raw `delivery_ratings` table read is still correctly denied for that same unrelated customer (RLS unchanged, only the narrow RPC opens this up)

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
- [ ] **Custom SMTP for `eziza-partners`** — auth emails (signup confirmation, password reset) currently ride on Supabase's default mailer, which is rate-limited and meant for dev/testing only. Hit its limit during real signup testing 2026-07-25/27. Needs a real provider (Resend, same one ZeeFashion uses) configured under Supabase Dashboard → Authentication → SMTP Settings before this is production-ready.

### ZeeFashion ↔ Eziza Integration — now complete, see the dedicated section above
- [ ] **Notifications reported as not firing at all** in latest live testing, despite the notification wiring for all 4 key events (ready-for-pickup, bid placed, bid accepted, rider arrival) being verified correct in code on both the internal and Eziza paths. Needs device-level debugging next: confirm `device_tokens`/FCM token registration actually happened for the test accounts, check `send-notification`'s logs for the actual FCM API response (not just that it was invoked), and check the Firebase project's APNs/FCM config is still valid. Do not assume the earlier code fixes are wrong until this is isolated — they closed real gaps, but something upstream (or the test device's token) is likely still broken.
- [x] Pass buyer phone number when ZeeFashion creates Eziza delivery — `store_update_tracking.dart` forwards both `pickup_contact_phone` and `delivery_contact_phone` through `logistics-gateway` to Eziza's `create-delivery`
- [x] Wire ZeeFashion merchant handoff confirm → Eziza `picked_up`
- [x] Extend `dispatch-webhook` — on `delivered`, fire tenant webhook so buyer sees confirm prompt
- [x] ZeeFashion `packageReceived()` calls back to Eziza → `confirmed`

### External Carriers / Shipbubble — BUILT 2026-07-29, full app-level E2E live-verified 2026-08-08
Customer-facing alternative to rider/company bidding: get instant courier quotes (DHL, GIG, etc.) and book directly, alongside the existing "Offers Received" section.

**Sandbox live-verification, 2026-08-08**: `SHIPBUBBLE_API_KEY` (a `sb_sandbox_...` key) and `SHIPBUBBLE_WEBHOOK_SECRET` were set in Supabase secrets — both to the *same* value, since Shipbubble's docs never document a webhook secret distinct from the API key, and the dashboard's "API keys & Webhook" settings page only ever shows the one key per mode (confirmed directly in the Shipbubble dashboard — no separate webhook-secret field exists anywhere). Verified live, direct against Shipbubble's API (not yet through Eziza's own edge functions — see below):
  - `address/validate` (sender + receiver), `fetch_rates`, and `shipping/labels` (real booking) all succeeded with real sandbox data — got back a real order id (`SB-1DC8F40B705E`).
  - Both **Live webhook url** and **Test webhook url** fields in the Shipbubble dashboard already correctly pointed at `https://nvwpsccleewgirlwokys.supabase.co/functions/v1/shipbubble-webhook` (verified character-for-character, and persisted across a page reload).
  - Fired Shipbubble's own webhook simulator (`POST /v1/shipping/labels/webhooks/:order_id`) against that real order — confirmed via Supabase's `function_edge_logs` (source `function_edge_logs`, not `edge_logs` — that one only carries REST/Auth gateway traffic) that the request hit `shipbubble-webhook` and got back **200**, not the 401 `"Invalid signature"` the function returns on a bad HMAC. That's conclusive: the shared-secret guess is correct and signature verification is genuinely working.

**Full app-level E2E, 2026-08-08**: mirrored the real customer flow exactly rather than testing Shipbubble in isolation — real Supabase Auth signup (`admin/users` + password sign-in, not a raw `auth.users` insert), a real `deliveries` insert in the *exact* shape `send_package_page.dart` uses (same `tenant_id`, same field set) issued with the customer's own JWT (RLS-respecting, not service-role), wallet seeded directly since that's the one step with no user-facing endpoint. Then hit the actual deployed edge functions with that JWT: `shipbubble-fetch-rates` → `shipbubble-book-shipment` → real Shipbubble webhook → `shipbubble-cancel`, checking real DB state after each step. All of it worked as designed once two real bugs (below) were fixed. Every throwaway row (customer, deliveries, bookings, quotes, wallet_transactions, auth user) was deleted after and confirmed gone.

  - **Real bug found + fixed: `shipbubble-webhook` had no `verify_jwt = false` in any committed config**, so it relied on whatever flag the *original* deploy happened to pass. Redeploying it via a plain `supabase functions deploy shipbubble-webhook` (no flag) silently flipped it back to requiring a Supabase JWT — Shipbubble's real webhook calls (no Supabase auth) then got rejected at the gateway with `401 UNAUTHORIZED_NO_AUTH_HEADER`, a **different, easily-confused-with-signature-failure error** than the function's own `401 "Invalid signature"`. Anyone redeploying this function in future **must** pass `--no-verify-jwt`, e.g.: `supabase functions deploy shipbubble-webhook --project-ref nvwpsccleewgirlwokys --use-api --no-verify-jwt`. No `config.toml` exists in this repo to enforce this automatically — worth adding one if this function gets redeployed often.
  - **Real bug found + fixed: the webhook's top-level `status` field can be stale.** Captured a real payload (via a temporary debug table, not the flaky log-analytics API — `POST /v1/analytics/endpoints/logs.all` intermittently errors or silently returns `[]` on `like`/`ilike` filters against `function_edge_logs`, unreliable for this kind of investigation) showing `"status":"confirmed"` at the top level while `package_status` (a chronological array of every transition) already ended in `{"status":"Completed",...}` — a retry/redelivery artifact from the `verify_jwt` breakage above, but a real scenario the code has to handle regardless of cause. Fixed: `shipbubble-webhook` now reads the *last entry of `package_status`* as the source of truth (lowercased, spaces→underscores to match `STATUS_MAP`'s keys), falling back to the old `status`/`data.status`/`event` chain only if `package_status` is absent. Re-verified by replaying the real captured payload against the fixed function: booking correctly landed on `completed`, delivery correctly flipped to `status='confirmed'`/`confirmed_at` set.
  - Confirmed real payload shape (previously just guessed): top-level `order_id` and `status` do exist as the code assumed, plus `package_status[]`, `courier`, `ship_from`/`ship_to`, `payment`, `tracking_url`, and `event: "shipment.status.changed"` — none of that was known before today.
  - `shipbubble-fetch-rates` → `shipbubble-book-shipment` needed no code changes — worked first try once given a valid delivery + wallet balance. Minor testing-only gotcha, not a code bug: Shipbubble's name validator rejects any digit/symbol in `name` fields (tripped by "E2E Sender" — the "2" — not by real names).
  - `shipbubble-cancel` verified correctly on a second fresh booking (booked, then cancelled pre-processing): wallet refunded exactly the debited amount, `refund_<order_id>` reference convention (the 2026-07-29 collision fix) confirmed still collision-free, booking landed on `status='cancelled'` with `cancelled_at` set.

- [x] Migration `20260729000000_external_carriers.sql`:
  - `deliveries.fulfillment_channel` (`'internal'` default | `'external_carrier'`) — `credit_delivery_earnings()` gets one more early-return guard (same shape as its existing `is_sandbox` check) so an externally-fulfilled delivery never reaches the rider/company earnings pipeline, since there's no rider/company to credit and the money flows *out* to the carrier instead.
  - `external_carrier_quotes` + `external_carrier_bookings` tables — locked down the same way every other customer-facing table in this project is (Phase 4 lesson: new tables inherit Supabase's default blanket grant otherwise) — `REVOKE ALL` + `GRANT SELECT` only, RLS scoped to `customer_id = auth.uid()`.
  - `reject_bids_on_external_carrier_deliveries` trigger on `delivery_bids` — mirrors ZeeFashion's own `reject_bids_on_eziza_requests` (same problem: a delivery can't be both externally booked and internally bid on).
  - `finalize_book_external_carrier` / `cancel_external_carrier_booking` RPCs — same precheck/finalize-after-external-success shape already proven for ZeeFashion's Eziza-bid-accept flow, and the same wallet-debit/refund convention as `pay_and_accept_delivery_bid` (insert into `wallet_transactions`, never a direct balance update alongside it).
  - **Real bug caught by testing before it shipped**: `cancel_external_carrier_booking`'s refund insert reused the same `shipbubble_order_id` as `reference` for both the original debit and the refund row — collided with `wallet_transactions`' unique index on `reference`, so every cancellation 500'd. Fixed (refund uses `'refund_' || shipbubble_order_id`), re-verified live: booking debits correctly, cancel refunds correctly back to the original balance, bid-rejection trigger confirmed working, all with throwaway customer/delivery/quote rows.
- [x] 5 new edge functions, all deployed and auth-smoke-tested (correctly return 503 "Shipbubble is not configured yet" rather than crashing, since `SHIPBUBBLE_API_KEY` isn't set pending approval):
  - `shipbubble-package-options` — cached proxy for Shipbubble's `package-categories`/`package-dimensions` reference data, so the customer picks from their real presets (not invented tiers) at booking time
  - `shipbubble-fetch-rates` — validates delivery ownership + `status='open'`, calls `address/validate` (sender + receiver) then `fetch_rates`, stores quote rows
  - `shipbubble-book-shipment` — prechecks wallet balance, calls `shipping/labels` create, only on success calls `finalize_book_external_carrier`; on a finalize failure after Shipbubble already created a real shipment, compensates by cancelling it on their side rather than leaving an unpaid shipment dangling
  - `shipbubble-cancel` — calls Shipbubble's `cancel-shipment` first (only works pre-processing per their docs), refunds via `cancel_external_carrier_booking` only on their confirmed success
  - `shipbubble-webhook` — verifies `x-ship-signature` (HMAC-**SHA512**, not the SHA256 used elsewhere in this project — Shipbubble's own scheme), maps their status events to booking status + reflects `completed`/`cancelled`/`picked_up` onto `deliveries.status`. Real payload shape + a stale-top-level-`status` gotcha confirmed live 2026-08-08 (see below) — reads `package_status[]`'s last entry as the source of truth now, not the bare `status` field. **Must be deployed with `--no-verify-jwt`** (see below) — no `config.toml` enforces this.
- [x] `lib/services/shipbubble_service.dart` + new "External Carriers" section in `customer_delivery_detail_page.dart` (next to the existing bids section, same gating): quote request → category/box-size picker sheet (options fetched live from `shipbubble-package-options`) → quote list → book (behind the same PIN-verification gate as accepting a rider bid, since it moves the same real money) → active booking card with tracking link + cancel action once booked.
- [x] `flutter analyze` clean across the whole `lib/` tree.
- [x] **App-level E2E live-verified 2026-08-08** (see above): `shipbubble-fetch-rates` → `shipbubble-book-shipment` → real webhook → `shipbubble-cancel`, all through the real deployed edge functions with a real customer JWT, real wallet debit/refund, real DB state checked at each step. Two real bugs found and fixed in the process (`verify_jwt` deploy gotcha, stale top-level webhook `status` field).
- [ ] **Not yet clicked through the actual Flutter UI** — today's verification drove the edge functions directly (real JWT, real requests) rather than tapping through `shipbubble_service.dart`'s screens in a running app. The categories/dimensions response field names used defensively in the Flutter picker (`shipbubble-package-options`) are still unconfirmed against what the picker sheet actually renders.
- [ ] **Known gap, deliberately not built**: a carrier-initiated cancellation (Shipbubble cancels on their end, not the customer via `shipbubble-cancel`) has no refund path in `shipbubble-webhook` yet — flagged directly in that function's own comments rather than guessing a refund flow without having seen a real cancellation webhook payload.
- [ ] **Terminal Africa (T-Ship API) — evaluated 2026-07-30, decision deferred, not started.** Raised as a possible replacement since Shipbubble's account is still stuck in approval. Public docs (`docs.terminal.africa/tship`) reviewed before writing any code: auth is a `Bearer SECRET_KEY` header (straightforward swap), and the shipment lifecycle (`draft/pending/confirmed/in-transit/delivered/cancelled`) would map onto our existing booking-status handling the same way Shipbubble's does. Architecturally compatible with the existing `external_carrier_quotes`/`external_carrier_bookings`/`fulfillment_channel` schema unchanged — nothing DB-side would need to move.
  - **Two real concerns found, not yet resolved:** (1) Terminal's own sample rate data and marketing lean heavily toward multi-day parcel/international shipping — DHL Express/FedEx/UPS/Sendbox, sample delivery times of "1–3 days" through "5–7 business days." Gokada (a real Nigerian same-day dispatch rider service) is listed as a carrier category, but nothing in the public docs confirms same-day local dispatch is actually bookable through the API rather than just named — and that's specifically what "Instant Courier" needs, not multi-day parcel shipping. (2) No public documentation on whether a *live* API key requires the same kind of business/KYC verification that's blocking Shipbubble — switching could just trade one approval wall for an identical one.
  - Also unconfirmed from public docs alone: exact webhook signature scheme (header/algorithm), and the precise Address/Parcel resource-creation payloads that come before requesting rates (Terminal's flow is more granular than Shipbubble's — you create an Address resource and a Parcel resource first, each getting its own ID, then request rates against those IDs — would need folding into our own rate-fetch call so the app-facing contract doesn't change).
  - **Current status, updated 2026-08-08:** the approval wall that motivated this evaluation is gone — Shipbubble's account is approved and its sandbox key + webhook signing are now live-verified (see above). No Terminal Africa code started, and switching no longer has an urgency driver; revisit only if a real gap in Shipbubble itself shows up during app-level E2E testing.
- [ ] **Admin panel — manage carriers + manual rate cards** — explicitly out of scope for this build, not requested.

### External Carriers — extended to tenants (ZeeFashion + eziza-partners) — BUILT 2026-07-30, same not-yet-app-level-E2E-tested caveat as above
Same feature as the customer-facing build above, extended so a **tenant's own buyer** can book one too (not just Eziza's direct customers). Two design questions settled first: (1) package weight/category is collected once at `create-delivery` time, not interactively — for ZeeFashion specifically, the **merchant** picks it at "Ready for Pickup" time, not the buyer; (2) a tenant must **prepay a balance with Eziza** before its buyers can use this (confirmed choice over "bill later" or "tenant uses its own Shipbubble account").

**Eziza side:**
- [x] Migration `20260730000000_external_carriers_for_tenants.sql`: `tenants.wallet_balance` + `tenant_wallet_transactions` (same incremental-trigger shape as every other wallet table in this project) · `deliveries.package_category_id`/`package_weight_kg`/`package_dimension` · `external_carrier_quotes`/`external_carrier_bookings.customer_id` made nullable with a new `tenant_id`, `CHECK` exactly one of the two is set · `finalize_book_external_carrier_for_tenant`/`cancel_external_carrier_booking_for_tenant` — mirror the customer RPCs but **no `auth.uid()` check** (there's no tenant JWT; trust boundary is the calling edge function's already-completed `validateApiKey()`) and **not granted to `authenticated`** (self-caught security gap: without the explicit revoke, any logged-in Eziza customer could have called these directly and drained an arbitrary tenant's wallet — verified closed via `information_schema.routine_privileges` + a live "permission denied" test).
- [x] Migration `20260730010000_guard_cancel_delivery_external_carrier.sql`: `cancel_delivery_with_refund()` now rejects an `external_carrier`-fulfilled delivery with a clear message pointing at the carrier-cancel endpoint instead, rather than silently refunding without ever cancelling the real Shipbubble shipment.
- [x] `customer_delivery_detail_page.dart`: `_canCancel()`/`_isTrackable()` now both exclude `fulfillment_channel == 'external_carrier'` deliveries too — the generic self-serve cancel button and live-GPS-map path don't know how to handle a real Shipbubble shipment; `_carrierBookingCard`'s own "Cancel Booking"/"Track shipment" link is the correct surface for that channel.
- [x] `create-delivery` extended with optional `package_category_id`/`package_weight_kg`/`package_dimension` — omitting them is fine, the delivery just isn't eligible for External Carriers later.
- [x] New edge functions: `tenant-shipbubble-package-options`, `tenant-shipbubble-rates`, `tenant-shipbubble-book` (prechecks `tenants.wallet_balance`), `tenant-shipbubble-cancel` — same `validateApiKey()` auth as `create-delivery`/`accept-bid`.
- [x] `shipbubble-webhook` also maps `picked_up` → `deliveries.status='picked_up'` now (previously only `completed`/`cancelled` touched it) — gives tenants the same granular status visibility internal rider deliveries already have, for free, via the existing generic `dispatch-webhook` relay (no new tenant-relay code needed).
- [x] eziza-admin: manual "Adjust Tenant Balance" (credit/debit + reason) on the Tenants page, same precedent as every other manual-admin-action in this project. Migration `20260730030000_tenant_topup_request.sql` adds `tenants.topup_requested_at`/`topup_requested_amount` — a tenant flipping "Request Top-Up" in eziza-partners surfaces a badge + banner here (pending requests sort to the top of the list, same as pending live-access requests); crediting the balance auto-clears the flag.

**ZeeFashion side:**
- [x] `supabase/migrations/20260730000000_eziza_carrier_quotes_and_rpcs.sql` + `20260730020000_carrier_booking_columns.sql`: `eziza_carrier_quotes` mirror table (never trust a client-supplied quote amount for a real charge, same reasoning as `eziza_delivery_bids`) · `precheck_accept_external_carrier`/`finalize_accept_external_carrier`/`refund_external_carrier_booking` RPCs (these ARE `auth.uid()`-checked and granted to `authenticated` — the buyer has a real Supabase JWT here, unlike the tenant-Eziza leg above) · `delivery_requests.fulfillment_channel`/`eziza_carrier_booking_id`/`carrier_tracking_url` columns so `refund_external_carrier_booking` only ever undoes a real carrier booking (never a normal bid-assigned delivery) and the UI can tell the two apart.
- [x] `logistics-gateway` — 4 new outbound actions (`get_package_options`, `get_carrier_rates`, `book_carrier`, `cancel_carrier_booking`), same ordering convention as the proven `accept_bid` action (external Eziza call commits first, local ZeeFashion charge second, compensating cancel on Eziza's side if the local charge fails).
- [x] `store_update_tracking.dart` — optional "Package Details" picker in the merchant's "Ready for Pickup" confirm sheet (Shipbubble's live category/box presets, fetched via `get_package_options`), forwarded through to `create-delivery`.
- [x] `track_order.dart` — new "Instant Courier" section next to the existing bid list (only for `eziza`-routed, still-`open` requests): get quotes → pay (wallet/card, same PIN-gated flow as bid acceptance) → active booking card with tracking link + cancel.
- [x] **Live-verified the full relay chain end-to-end** with throwaway rows on both DBs (not mocked): drove a real `deliveries.status` transition through Eziza's actual `dispatch_on_delivery_update` trigger → `dispatch-webhook` → a real HTTP POST to ZeeFashion's production `logistics-gateway` → confirmed `delivery_requests.status` updated correctly for both `picked_up` and `cancelled` (the latter also correctly auto-refunding the wallet via the existing guarded paid→refunded flip). All test rows cleaned up afterward on both sides.
- [x] `flutter analyze` clean on both `zeefashion` and `eziza_rider` (0 errors either app).

**eziza-partners:**
- [x] Dashboard "Wallet Balance" card (read-only `tenants.wallet_balance`) + "Request Top-Up" button (optional amount, mirrors "Request Live Access" — flags to admin, moves no money itself).
- [x] `docs/integration-guide.html` updated: the 3 new `package_*` fields on `create-delivery`, and a full "External Carriers" endpoint section (`tenant-shipbubble-package-options`/`-rates`/`-book`/`-cancel`).

**Known gaps carried over from the customer-facing build (not re-solved here):**
- [ ] Same carrier-initiated-cancellation refund gap noted above — applies equally to a tenant's own wallet (no credit-back path if Shipbubble cancels a tenant-booked shipment on their end, as opposed to the tenant calling `tenant-shipbubble-cancel` itself, which does refund correctly).
- [ ] Still blocked on real Shipbubble account approval for true end-to-end testing (real rates/booking/webhooks) — everything reachable without a live account (auth wiring, money movement both directions, guard triggers, the full webhook-relay chain) was verified live.

### Tenant API / Developer Experience
- [ ] **Rename `bid` → `offer` in the API** — the app's own UI was renamed from "bid" to "offer" a while back, but `accept-bid`, `delivery_bids`, `bid_id`, and the `bid.placed` webhook event never got the same treatment. Deferred for now: a real rename would touch 4 edge functions (`accept-bid`, `dispatch-bid-webhook`, `notify-bid-accepted`, `notify-bid-placed`) plus the `delivery_bids` table's RLS/triggers/indexes, and would need a coordinated breaking-change deploy with ZeeFashion's `logistics-gateway`, which already calls `accept-bid`/`bid_id` in production. For now just documented as a terminology note in `docs/integration-guide.html`.
- [ ] **No `list-bids`/`list-offers` endpoint** — a tenant can only discover offers on a delivery via the `bid.placed` webhook; there's no way to fetch existing ones (e.g. after a missed webhook, or if their receiver comes online late). Noted as a known limitation in the integration guide; would need a new tenant-facing edge function if requested.
- [ ] **E-commerce platform plugins (WooCommerce/Magento/OpenCart) — discussed 2026-07-15, not started.** Pure client-side add-ons on top of the existing tenant API (create-delivery/get-delivery/webhooks/sandbox) — no backend changes needed. WooCommerce first if ever built: largest install base among Nigerian SME stores, self-install for non-technical store owners (a real access unlock, same reasoning Shipbubble's own WooCommerce plugin presumably followed), best-documented shipping-method plugin API. Magento/OpenCart explicitly lower priority — smaller/more-enterprise userbase for the build/maintenance cost — build only if a real merchant asks.
- [ ] **Native mobile SDKs (Android/iOS/Flutter) — discussed 2026-07-15, not started, lower priority than the plugins above.** No external tenant has asked; a tenant building their own app can already hit the REST API + webhooks directly (same path ZeeFashion's Flutter app already uses), so an SDK is developer-convenience polish, not an access unlock like the CMS plugins are — and three SDKs is 3x the ongoing maintenance/versioning/store-publishing surface for a narrow audience. If ever built, Flutter first (its realtime GPS-tracking/map logic could be extracted from `rider_map_page.dart`/`delivery_tracking_page.dart` with little new code), native Android/iOS only for a specific tenant that can't use Flutter. Revisit only if a second external tenant actually asks — same "later" bar as [[project_eziza]] Terminal Africa note above.

### Monetisation
- [ ] Commission deduction in `pay_and_accept_delivery_bid` RPC
- [ ] Markup on external carrier quotes
- [ ] `delivery_fee_breakdown` jsonb column on `deliveries`
- [ ] Admin earnings dashboard
- [x] **Uncollected-commission gap: a partner's delivery fulfilled by an Eziza rider/company — FIXED + live-verified 2026-08-11.** Confirmed by tracing the actual money flow (user asked for a full audit after sensing something was off between Eziza Direct, Eziza Partners, and Shipbubble): when a tenant like ZeeFashion routes a delivery to an *Eziza rider/company* (not Shipbubble), the tenant collected the full delivery fee from its own customer, but Eziza's own `accept-bid` edge function never touched money at all — the rider/company still got paid in full once confirmed, with nothing ever collected from the tenant. Documented as a *known, previously-accepted* trade-off in `20260730000000_external_carriers_for_tenants.sql` (External Carrier bookings were deliberately required to prepay *because* this gap already existed), but decided 2026-08-11 to close it rather than leave it accepted, going with the option that reuses existing infrastructure: **option (2)** from the original TODO — draw from the tenant's existing prepaid wallet at accept time, same mechanism External Carrier already uses.
  - New RPC `accept_bid_for_tenant` (migration `20260811000000_accept_bid_for_tenant_debits_wallet.sql`) — atomically debits `tenants.wallet_balance` the bid amount, accepts the winning bid, rejects siblings, and assigns the delivery, all row-locked (delivery + bid + tenant) so a retried call can't double-debit. Hard-blocked with `'Insufficient tenant balance'` if the balance can't cover it — same guard shape as `finalize_book_external_carrier_for_tenant`.
  - `accept-bid` edge function rewritten to call this RPC instead of doing plain status updates with no payment step. Insufficient-balance is translated to the same customer-safe message `tenant-shipbubble-book` already uses (`"This delivery option is temporarily unavailable. Please choose a different one."`) — the real cause (tenant's own prepaid balance, not the buyer's) stays visible to the tenant via their own `eziza-partners` dashboard, never leaked to the tenant's own customer, since ZeeFashion's `logistics-gateway` forwards this error message verbatim to the Flutter customer app.
  - **Live-verified against the real deployed function + RPC** with a fully throwaway tenant, rider, delivery, and bid: insufficient balance correctly blocked with the friendly message and zero side effects (checked wallet/delivery/bid/ledger all untouched); sufficient balance correctly debited the tenant (5000 → 2000 on a 3000 bid), accepted the bid, assigned the delivery, and recorded one `tenant_wallet_transactions` row; retrying the same accept on the now-`assigned` delivery correctly blocked with no double-debit. All throwaway rows cleaned up after.
  - **Not yet touched, deliberately out of scope for this fix**: Shipbubble's own no-markup pass-through (options 2 and 4 from the original money-flow map) — that's missed margin, not an active loss, and a separate decision.

- [x] **Auto-recharge for tenant wallets — BUILT + LIVE-VERIFIED 2026-08-11.** Motivation: a high-volume tenant can't sensibly guess a lump sum to prepay, and now that internal-rider deliveries also debit the wallet at accept time (not just External Carrier bookings), that balance drains faster and more often. Went with an opt-in toggle rather than invoicing/postpaid, which would have re-opened the same "Eziza fronts money with no guaranteed collection" exposure the debit-at-accept fix closes.
  - Opt-in toggle in `eziza-partners`' Overview page (default OFF — every tenant keeps today's manual top-up behavior unless they turn it on) — "When my balance drops below ₦X, automatically charge my card ₦Y." Same UX pattern Twilio/AWS use for exactly this problem. Requires a saved card first (captured automatically off the tenant's own most recent top-up, no separate "save my card" step) — the toggle is disabled with an explanatory note until one exists.
  - `tenants` gains `auto_recharge_enabled`/`threshold`/`amount`, `paystack_authorization_code`, and cooldown/daily-cap bookkeeping columns (migration `20260811020000_tenant_auto_recharge.sql`). New trigger `auto_recharge_tenant_wallet()` (`AFTER UPDATE OF wallet_balance ON tenants`) fires only on a decrease crossing below the tenant's own threshold — guarded by a 2-minute cooldown and a hard 5/day cap against a bug repeatedly charging a real card — then calls the new `tenant-auto-recharge` function via `net.http_post` (Eziza's project has `pg_net` available). Deliberately does **not** embed the service-role key in the migration file itself (unlike the existing precedent in ZeeFashion's own `trigger_new_order_notification`, a real secret-exposure risk not worth repeating) — reads it from `supabase_vault` by name instead, stored once via `vault.create_secret()` outside of any committed file.
  - `tenant-auto-recharge` charges the tenant's saved Paystack authorization (`POST /transaction/charge_authorization`) with the same `metadata.purpose = 'tenant_topup'` the manual top-up flow already uses, so `paystack-webhook`'s existing `tenant_topup` branch credits it automatically with zero changes needed there. `paystack-webhook` now also captures a reusable `authorization_code` off any successful top-up event (`data.authorization.reusable`).
  - **Live-verified against the real deployed trigger + function**: fired correctly on a qualifying decrease — confirmed via `net._http_response` that Paystack cleanly rejected a deliberately fake authorization code (`AUTH_fake_test_code_123`), proving the full trigger → `net.http_post` → function → Paystack chain without any risk of an actual charge. Cooldown correctly blocked an immediate re-fire (charges-today counter unchanged), an increase (simulated recharge credit) correctly did not fire, disabling correctly stopped firing, and the daily cap correctly blocked a 6th attempt. UI live-verified in the browser as the real ZeeFashion tenant (temporarily set then reverted a fake authorization code to see the enabled state): empty state, form, save, and turn-off all confirmed working; the real tenant row was restored to its exact original state afterward.

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
- [x] `lib/pages/home/company_profile_page.dart` — new, company's first-ever post-registration edit page: hero header with status badge, Company Info, Location, photo upload. Wired "Edit Profile" + "Change Password" tiles into the Account tab for the first time.
- [x] **Photo upload uses Eziza's own Bunny CDN zone** (`lib/services/bunny_service.dart`, `eziza.b-cdn.net`, already used for rider docs at `rider-docs/<uid>/...`) — **correction 2026-07-13**: briefly built a Supabase Storage bucket + RLS policies for this before realizing Eziza already had its own Bunny zone (an earlier note in this doc wrongly said it didn't); reverted that (migration `20260713010000`) in favor of `BunnyService.upload()`.
- [x] Migration `20260713020000` — `avatar_url` on `riders`/`companies`, and `companies`' first-ever column-level UPDATE grant (previously zero — nothing could update a company row post-registration at all)
- [x] **Bank Account — correction 2026-07-14**: first built as a section embedded within each role's profile page; the user explicitly called this the wrong call ("i thought it was suppose to be detach from the profile") and asked for it split out. Now `lib/pages/shared/bank_account_page.dart` — one shared, role-parameterized (`BankAccountRole.rider`/`.company`) page with its own Account-tab tile ("Bank Account", separate from "Edit Profile") and its own independent save action for both roles. `SupabaseService.updateRiderProfile()`/`AuthController.updateProfile()` no longer take bank params — split into a new `updateRiderBankDetails()`/`updateBankDetails()` pair so Personal Info/Vehicle save and Bank Account save no longer touch the same request. The "no bank details yet" payout-gate prompts on both dashboards now navigate straight into `BankAccountPage` instead of just showing a snackbar.
- [x] **Second correction, same day — rider bank_code was missing entirely**: the first pass gave riders a free-text "Bank Name" field (matching the old embedded section) while companies got the `BankService` dropdown. User caught this: admin/Paystack transfer payouts resolve by bank *code*, not by a typed bank name, so riders needed the same dropdown. Turned out `riders` never had a `bank_code` column at all — even `rider_application_page.dart`'s registration flow already showed a bank picker and silently dropped the selected code on submit, a pre-existing gap from before this session. Fixed with migration `20260714000000_rider_bank_code.sql` (adds `riders.bank_code`, extends the column-level UPDATE grant from `20260712070000` to include it), `Rider.bankCode` added to the model, `SupabaseService.applyAsRider()`/`updateRiderBankDetails()` and their `AuthController` wrappers now take `bankCode`, `rider_application_page.dart` now passes `_selectedBank?.code`, and `BankAccountPage` uses the same `BankService` dropdown for both roles (no more free-text bank name anywhere). Existing riders with a `bank_name` but no `bank_code` (registered before this fix) get a best-effort match-by-name on load so they aren't forced to re-enter from scratch, but will need to re-confirm their bank once to actually populate `bank_code`.
- [x] `flutter analyze` clean across the whole `lib/` tree
- [x] **Live-verified 2026-07-13** with throwaway test accounts: full company field set (name/contact_person/phone/cac_number/state/city/avatar_url) updates correctly in one request; `wallet_balance`/`is_approved`/`status` confirmed untouched by the same request
- [x] **Bank Account split live-verified 2026-07-14** with throwaway rider + company test accounts: bank-only update and personal/company-info-only update persist independently through separate requests, confirmed neither clobbers the other's fields
- [x] **Rider bank_code live-verified 2026-07-14**: throwaway rider account confirms `bank_code` persists on a legit bank-only update, and a mixed request adding `wallet_balance`/`is_approved` alongside a legit `bank_code` still gets rejected (403, column-grant lockdown from `20260712070000` intact)
- [ ] Not yet clicked through in the actual app UI (photo picker, bank dropdown, save flows for all 3 roles) — only the DB-layer writes are live-verified
- [x] **Rider avatar-save regression found + fixed 2026-07-17**: user reported individual + company-employed rider photo uploads silently not saving, while company avatar upload worked fine. Root cause: `20260714000000_rider_bank_code.sql`'s `REVOKE UPDATE ON public.riders FROM authenticated` + fresh `GRANT UPDATE (...)` (to add `bank_code`) forgot to re-list `avatar_url`, silently regressing the grant `20260713020000_rider_company_avatar.sql` had added the day before — Bunny upload succeeded, but the Supabase `UPDATE` afterwards touched 0 rows under the missing column privilege. `companies.avatar_url` was untouched by that migration, which is exactly why company avatar upload kept working. Fixed with migration `20260717000000_fix_rider_avatar_grant_regression.sql` (re-grants `UPDATE (avatar_url) ON riders`), live-verified with a throwaway rider account (PATCH `avatar_url` as the rider's own JWT → 200, value persisted).
- [x] **Avatar re-upload not reflecting, found + fixed 2026-07-18**: after the grant fix above, user reported the first photo upload works but selecting a *second* photo doesn't update. Root cause: all 3 avatar upload call sites (`profile_page.dart` rider, `company_profile_page.dart`, `edit_profile_page.dart` customer) uploaded to a fixed Bunny path (`avatars/<uid>/photo`), so every re-upload produced the exact same public URL — both Bunny's CDN edge cache and `cached_network_image`'s local disk cache keep serving the old bytes for an unchanged URL even though the underlying file changed and the DB row was written correctly. Fixed by timestamping the storage path (`avatars/<uid>/photo_<epoch_ms>`) at all 3 sites, so every upload is a genuinely new URL — same cache-busting convention `ticket_thread_page.dart`'s attachment upload already used, just not applied to avatars yet. Old avatar files are left orphaned on Bunny storage rather than overwritten (acceptable storage-cost tradeoff, matches the ticket-attachment precedent); not yet re-verified by clicking through the actual app.

### Phone number moved from signup to Send Package — BUILT + live-verified 2026-07-18
User wanted phone removed from the initial signup form (friction for a field not needed yet) and asked for later instead, at the point it's actually required. Investigated first rather than assuming: `customers.phone` was already nullable (built that way since Phase 3), and Send Package already has its own editable "Sender Phone" field (pre-filled from account metadata) — it just wasn't required. Riders/companies needed no changes at all: their phone is collected during the separate rider/company **application** (a later, already-gated step, `riders.phone`/`companies.phone` are NOT NULL), so "before accepting an order" was already effectively enforced for them.
- [x] `register_page.dart` — removed the Phone Number field/controller/validator entirely from the signup form
- [x] `AuthController.registerUser()` / `SupabaseService.registerUser()` / `register-user` edge function — `phone` param dropped end-to-end, no longer a required field anywhere in the signup chain
- [x] `send_package_page.dart` — "Sender Phone" is now a required field (blocks submission with a snackbar, same pattern as the existing required "Recipient Phone"); on submit, if the entered phone differs from what's on the account, it's saved back to both `customers.phone` and auth `user_metadata` (non-fatal if that save fails — the delivery's own `pickup_contact_phone` still records it regardless) so the customer isn't asked again next time
- [x] `flutter analyze` clean across the whole `lib/` tree
- [x] **Live-verified 2026-07-18**: called the redeployed `register-user` function directly with no phone in the payload → 200, account created; confirmed the resulting `auth.users.user_metadata` has no `phone` key at all and the auto-created `customers` row has `phone: null`, no NOT NULL violation anywhere in the chain

### Premium card redesign (delivery/bid/earnings/rating/etc cards, all 3 roles) — BUILT, NOT YET COMMITTED
User said the cards looked "ugly" and "unwelcoming," asked for fancy/premium. Scoped to delivery-related first (agreed with user), then extended to job history/rider list/invite/rating cards on request.
- [x] New shared toolkit `lib/widgets/premium_card.dart` — `PremiumCard` (floating shell, soft diffuse double shadow, no hard border, real `InkWell` ripple), `IconBadge` (gradient-tinted circular icon), `StatusPill`/`InfoPill` (solid gradient-filled pills instead of tinted-outline chips), `RouteTimeline` (compact Uber-style pickup→dropoff dot-line-dot), `MoneyTag`, `PremiumButton` (gradient CTA with glow + ripple, optional `iconColor` override)
- [x] Reskinned: rider job feed card, active delivery card, wallet hero card, job history card, invite card, my-ratings card; customer delivery list card, incoming delivery card; company open-delivery/active/pending-bid/history/rider-list/invite/rating cards; the bid/offer card on `customer_delivery_detail_page.dart`; earnings + payout history cards; both wallet balance cards (customer + rider); `company_rider_ratings_page.dart`'s rating card
- [x] "View Route on Map" button converted to `PremiumButton` (was a plain `GestureDetector`+`Container`) so its padding matches "Mark Delivered" exactly, per explicit user ask — added `PremiumButton.iconColor` to preserve the gold map-pin icon on its navy background
- [x] `flutter analyze` clean across the whole `lib/` tree throughout; live smoke-tested once via iOS simulator (app launched clean, no exceptions, screenshot confirmed new styling render correctly) — not re-tested since further edits landed on top
- [ ] Not committed to git yet — large diff across ~15 files, holding for explicit go-ahead

### Rider Jobs tab / Company Deliveries tab — dynamic section ordering — BUILT, NOT YET COMMITTED
User ask, both roles: when there are new open jobs to act on, that section should lead; when there are none, the other section(s) should lead instead.
- [x] `rider_dashboard_page.dart` Jobs → Active sub-tab: "Open for Offers" leads (followed by "In Progress") when `_openDeliveries.isNotEmpty` and not a company-employed rider; otherwise "In Progress" leads and "Open for Offers" (empty state) trails. Company-employed riders are unaffected (they never see the Open for Offers section at all — their company bids for them).
- [x] `company_dashboard_page.dart` Deliveries → Active sub-tab: same pattern — "Available Deliveries" leads when `_openDeliveries.isNotEmpty`, otherwise "Active Deliveries"/"Your Pending Offers" lead and "Available Deliveries" (empty state) trails.
- [x] `flutter analyze` clean on both files
- [ ] Not committed to git yet

### Company rating showing unrounded raw decimal — found + fixed 2026-07-17
User reported a company's own rating displaying as `4.333333333333333333` instead of `4.3`. Two spots in `company_dashboard_page.dart` (wallet-card rating stat, account-tab stat cell) interpolated `company['rating_avg']` directly into a `Text` with no `.toStringAsFixed(1)` — every other rating display in the app (rider-side, `_bidCard`, rating pages) already rounded correctly; these two were the only unrounded holdouts. Fixed both to `.toStringAsFixed(1)`. `flutter analyze` clean. Not committed to git yet (bundled with the premium-card-redesign diff, same files).

### Customer can see bidder's photo + ratings before accepting — BUILT + live-verified 2026-07-18
User ask: show the rider's/company's uploaded photo on each bid/offer, and let the customer tap through to see that rider's/company's rating history before accepting.
- [x] Migration `20260718000000_public_ratings_rpc.sql` — `get_public_ratings(p_ratee_type, p_ratee_id)` SECURITY DEFINER RPC, granted to `authenticated`. Deliberately narrower than opening the raw `delivery_ratings` table to everyone: anonymised (no `rater_name`/`rater_auth_id`), rider-ratings only (a company's reputation is always derived from its fleet via the same `company_rider_invites` join `credit_rider_rating()` already uses — there's no `ratee_role='company'`).
- [x] `customer_delivery_detail_page.dart` — bid queries now select `avatar_url`/`rating_count` for both `rider`/`company`; `_bidCard`'s avatar shows the real photo (`CachedNetworkImageProvider`) when uploaded, falling back to initials; avatar+name+rating block is now tappable, opening the new `PublicRatingsPage`
- [x] New `lib/pages/customer/public_ratings_page.dart` — aggregate rating header + live-fetched anonymised review list via the RPC, same `PremiumCard`/`StatusPill` visual language as `CompanyRiderRatingsPage`
- [x] **Found + fixed a RenderFlex crash introduced by this same feature**: wrapping the bid card's avatar/name block in a `GestureDetector` left a `Row` (containing an `Expanded`) as a non-flexible direct child of the outer `Row`, giving it unbounded width — "RenderFlex children have non-zero flex but incoming width constraints are unbounded." Fixed by wrapping the `GestureDetector` in `Expanded`. Reformatted the file with `dart format` afterward.
- [x] `flutter analyze` clean across the whole `lib/` tree
- [x] **Live-verified 2026-07-18**: RPC called against a real rider with existing ratings returns correct anonymised rows for a totally unrelated throwaway customer account (200); confirmed raw `delivery_ratings` table read is still correctly denied for that same account (RLS unchanged, only the narrow RPC opens this up)
- [ ] Not committed to git yet

### Phase 6 — Support Tickets (all 3 roles + admin reply) — BUILT + live-verified 2026-07-14

**Found and fixed a real, unrelated bug while wiring image attachments**: `BunnyService._uploadBase` read `dotenv.env['BUNNY_STORAGE_URL']`, a key that was never actually set anywhere in `.env` — every `BunnyService.upload()` call in the shipped app (avatars, rider registration docs) has been silently failing since it was written (empty base → relative-only URI → request never reaches Bunny). Fixed to build the upload base from `BUNNY_STORAGE_ZONE_NAME` instead (which *is* set), live-verified end-to-end with a real curl PUT/GET/DELETE against the Bunny zone before touching the code.

- [x] Migration `20260715000000_support_tickets.sql` — `support_tickets`/`support_messages`, ported from ZeeFashion's schema, adapted to reference `auth.users` directly (no unified `profiles` table in Eziza). Category list swapped for logistics-appropriate values (`delivery_issue`/`payment_issue`/`refund_issue`/`account_issue`/`rider_issue`/`technical_issue`/`other` — no orders/products in Eziza). `image_url` included from day one instead of as a follow-up migration like ZeeFashion needed. `touch_support_ticket()` trigger is `SECURITY DEFINER` from the start (the session's now-standard lesson) since the inserting user has no UPDATE policy on `support_tickets`. RLS: users see/insert only their own tickets/messages, no UPDATE policy for users at all (status changes are admin-only, via the service-role key) — safe by omission, verified empirically (a user's PATCH attempt on their own ticket's status returns 200 but affects zero rows). Realtime added for `support_messages`.
- [x] Flutter: `lib/pages/shared/support_tickets_page.dart`/`create_ticket_page.dart`/`ticket_thread_page.dart`, one shared set for all 3 roles (Eziza's `support_tickets.user_id` is just the auth uid — no role-awareness needed client-side). Image attachments via `BunnyService.upload()` at `support/<uid>/<timestamp>`, not the raw hardcoded-key HTTP PUT ZeeFashion's version uses. Wired into all 3 roles' "Help & Support" tiles (`rider_dashboard_page.dart`, `company_dashboard_page.dart`, `customer_dashboard_page.dart`), replacing the WhatsApp/"Coming Soon" stub.
- [x] eziza-admin: real two-pane list+thread page at `/dashboard/support` (replacing the Phase-2 placeholder), backed by 3 new Route Handlers — `/api/admin/support` (GET list with identity resolution + PATCH status), `/api/admin/support/messages` (GET thread + mark-read, POST admin reply with auto open→in_progress + `notifyAuthUser()` push), `/api/admin/support/upload` (server-side Bunny PUT, keeping the Bunny key out of the browser bundle — unlike ZeeFashion admin's version, which hardcodes it client-side). Identity resolution: every auth user already has a `customers` row (Phase 3's trigger creates one for everyone), so that's the base name/phone; riders/companies additionally get a role label if a matching row exists.
- [x] Added Bunny storage credentials (`BUNNY_STORAGE_API_KEY`/`BUNNY_STORAGE_ZONE_NAME`/`BUNNY_STORAGE_PULL_ZONE`) to `eziza-admin/.env.local`, copied from `eziza_rider/.env` with explicit user go-ahead (asked first — this is a live secret being duplicated into a second project).
- [x] Fixed a real bug in `lib/adminFetch.ts` surfaced by adding the image-upload call: it unconditionally set `Content-Type: application/json` on any request with a body, which would have broken the multipart upload (needs the browser's own boundary-bearing content type) — now skips that default when the body is `FormData`.
- [x] `flutter analyze` clean; eziza-admin `npm run build` clean, `npm run lint` clean (0 errors — 2 new `react-hooks/set-state-in-effect`/`exhaustive-deps` warnings match the same pre-existing, deliberately-not-restructured pattern already on every other admin page, plus one `no-img-element` warning matching ZeeFashion admin's own raw `<img>` usage)
- [x] **Live-verified 2026-07-14** end-to-end with throwaway rider/customer/admin accounts against the real dev server: ticket creation + opening message, `updated_at` trigger bump, RLS isolation (a second user gets `[]` reading someone else's ticket, 403 trying to insert a `sender_type='admin'` message), admin reply via the real `/api/admin/support/messages` route (auto-flips `open`→`in_progress`, message appears in the user's own RLS-scoped read), status PATCH via `/api/admin/support`, and confirmed a user's own attempt to PATCH their ticket's status returns 200 but changes nothing (no UPDATE policy). All throwaway rows/auth users cleaned up after.
- [ ] Not yet clicked through the actual native app UI or the admin browser UI by a human — verified via direct DB/API calls only, matching this session's established bar for "live-verified" (same rigor as Phases 2-5)

**Note:** the notification bug in the Pending section above is a separate track from these phases — it's a live bug in already-shipped Phase 1 functionality, not new scope. Worth fixing before or alongside Phase 2, since an admin dashboard doesn't help if the underlying app can't notify anyone.

### Pre-auth flow: Splash, Onboarding, Welcome — BUILT 2026-07-15

The app had no branded entry flow at all — a fresh install went straight to `LoginPage` with a "Rider Portal" subtitle (already caught and fixed once this session, see the git log), which was itself the wrong first screen even fixed, since a company or customer install shouldn't open on a login form before ever explaining what Eziza is. Ported ZeeFashion's actual proven structure (`splash_page.dart` is currently dead code there, unused — the real flow is the file-flag onboarding check → `WelcomePage`/`Login`/`SignUp`/`ForgotPassword`/`ResetPassword`), adapted for Eziza:

- [x] **No photography assets exist for Eziza** (checked `assets/images/` — only 2 debug screenshots, no hero/onboarding photos). Used gradient + large-icon compositions instead, matching the icon+gradient "hero" visual language already established across the rest of the app (profile/bank-account/change-password pages) rather than fabricating or sourcing photos.
- [x] `lib/pages/auth/splash_page.dart` — new, brief branded screen, checks the onboarding file-flag then routes to `OnboardingPage` (first run) or `AuthRouter` (returning).
- [x] `lib/pages/auth/onboarding_page.dart` — new, 3-slide swipeable intro (send/track/earn), full-bleed gradient + icon per slide, glass bottom card, page dots, skip — structurally ported from ZeeFashion's `onboarding_screen.dart`. Sets `.onboarding_done` via `path_provider` (new dependency — deliberately not `shared_preferences`, matching ZeeFashion's documented reason: an earlier ZeeFashion bug had an unrelated page resetting the flag via SharedPreferences on every load).
- [x] `lib/pages/auth/welcome_page.dart` — new, hero + "Create Account"/"Sign In" CTAs, shown to anyone not logged in. `AuthRouter`'s not-logged-in branch now returns this instead of `LoginPage` directly.
- [x] `lib/pages/auth/login_page.dart` — full visual rework to match ZeeFashion's polish (glow gradients, entrance animation, proper field styling); "Forgot Password?" now actually works (was previously a dead `onPressed: () {}`).
- [x] `lib/pages/auth/forgot_password_page.dart` / `reset_password_page.dart` — new. Forgot-password calls `resetPasswordForEmail(redirectTo: 'eziza://reset')`; reset page reached via `Supabase.instance.client.auth.onAuthStateChange`'s `passwordRecovery` event in `main.dart` (Supabase's own deep-link handling catches `eziza://reset`, already registered natively alongside `eziza://wallet-topup-complete` for Paystack — no new URI-stream listener needed, same technique ZeeFashion already proved out).
- [x] `lib/pages/auth/register_page.dart` — light header/style pass to match (back button, "GET STARTED" label treatment) without touching its existing fields or submit logic.
- [x] `main.dart`: `EzizaRiderApp` converted to `StatefulWidget` to host the `onAuthStateChange` listener; `home:` is now `SplashPage` instead of the auth router directly; `_AuthRouter` renamed to public `AuthRouter` (referenced by the new pages).
- [x] `flutter analyze` clean across the whole `lib/` tree.
- [ ] **Needs a real on-device test for the email-link → deep-link → reset-password step specifically** — everything else in this flow was verified by code review + `flutter analyze` (can't simulate tapping a real emailed link from this environment). Also needs the Supabase Dashboard's Authentication → URL Configuration → Redirect URLs to include `eziza://reset` (or `eziza://**`) — this is a project-level Auth setting, not something in a migration file, and I have no visibility into whether it's already set.
- [x] **Fixed 2026-07-15**: `wallet_page.dart`'s `AppLinks` listener matched on `uri.scheme == 'eziza'` only, so an `eziza://reset` link tapped while the wallet page happened to be open would have incorrectly triggered a "Checking your payment…" toast + wallet reload. Now also checks `uri.host == 'wallet-topup-complete'`.

### Account Deletion & EULA (Apple App Store compliance) — BUILT + live-verified 2026-07-16

Apple Guideline 5.1.1(v) requires in-app account deletion for any app that supports account creation. Also added an EULA, linked from signup per explicit request.

**Account deletion — the design was forced by empirical testing, not assumption.** Queried this project's actual live FK constraints (`information_schema`, via a throwaway `debug_check_fk_behavior` RPC, dropped after use) and found:
- `customers.id → auth.users(id) ON DELETE CASCADE`, but `wallet_transactions.customer_id → customers(id) ON DELETE NO ACTION`
- `deliveries.rider_id`/`delivery_bids.rider_id`/`earnings_ledger.rider_id`/`rider_payout_requests.rider_id` → `riders(id) ON DELETE NO ACTION`
- `earnings_ledger.company_id` → `companies(id) ON DELETE NO ACTION`

Live-tested three approaches against a throwaway account with real delivery/wallet history attached before writing any app code:
1. `auth.admin.deleteUser(uid)` (hard delete) — fails outright the moment any `wallet_transactions` row exists (true for anyone who's ever paid for or been paid for a delivery — the common case): `500, "violates foreign key constraint wallet_transactions_customer_id_fkey"`.
2. `?should_soft_delete=true` — despite the name, still attempts a real delete under the hood and fails identically for the same reason. Confirmed by testing both with and without a `wallet_transactions` row attached: without one it "succeeds" (misleadingly, since nothing blocked the cascade); with one it 500s.
3. **Permanent ban** (`auth.admin.updateUserById(uid, { ban_duration: '876000h' })`) — never issues a DELETE against `auth.users` at all, so no FK cascade is ever attempted, regardless of history. Verified: login blocked (`user_banned`), all history-holding rows (`customers`, `wallet_transactions`) untouched.

So the shipped design: **never delete `auth.users`.** Anonymise PII on `customers`/`riders`/`companies` (rows survive — required for delivery/bid/earnings/wallet referential integrity, which other parties and the business have a legitimate ongoing interest in), delete `device_tokens`, then permanently ban the auth user. Same trade-off ride-sharing/delivery apps commonly make for this exact reason.

- [x] `supabase/functions/delete-account/index.ts` — new edge function, verifies the caller's own JWT, anonymises whichever of `customers`/`riders`/`companies` rows exist for them, clears `device_tokens`, bans permanently. Deployed.
- [x] **Real bug caught by testing, not by review**: the first version set `phone`/`email`/`contact_person` to `null` on `riders`/`companies` without checking the UPDATE's error — `riders.phone` and `companies.email`/`phone`/`contact_person` are all `NOT NULL`, so the whole anonymisation silently failed while the ban still succeeded (account got banned with zero PII actually scrubbed). Caught by adding temporary debug instrumentation to the function, live-testing again, and reading the real error message instead of assuming success from the `{"ok":true}` response. Fixed (those columns use `''` instead of `null`), debug instrumentation stripped before final deploy, and now every step's error is checked and surfaced instead of being silently swallowed.
- [x] `lib/pages/shared/delete_account_page.dart` — new, shared across all 3 roles. Explains what happens in plain terms (permanently signed out, PII removed, delivery/payment records involving other people kept but unlinked from personal info), requires typing `DELETE` to enable the button (stronger friction than a plain confirm dialog, appropriate for an irreversible action).
- [x] "Delete Account" tile added next to "Sign Out" in all 3 dashboards' Account tabs (rider/company/customer).
- [x] `lib/pages/shared/eula_page.dart` — new, content structurally ported from ZeeFashion's `policy.dart` EULA sections, adapted for Eziza's logistics context (added Delivery & Package Handling and Wallet & Payments sections neither needed in a fashion marketplace; dropped nothing).
- [x] EULA link added to `register_page.dart` ("By creating an account you agree to our End-User License Agreement", tappable, matches ZeeFashion sign_up.dart's pattern) — this is the one place an Eziza account actually gets created; rider/company applications add role data to an already-existing, already-agreed account, so didn't need their own link.
- [x] Also added a standing "End-User License Agreement" tile to all 3 dashboards' Support sections, so it's reachable after signup too, not just during it.
- [x] `flutter analyze` clean.
- [x] **Live-verified 2026-07-16** end-to-end for all 3 role paths (customer-only, rider, company), each with a throwaway account: called the real deployed edge function with a real JWT, confirmed PII correctly anonymised (`full_name`/`phone`/`email`/bank details/docs all scrubbed), confirmed delivery/company rows with real history survive untouched, confirmed login fails with `user_banned` immediately after. All throwaway rows/auth users cleaned up after.
- [ ] Not yet clicked through the actual app UI by a human (type-DELETE-to-confirm flow, EULA page rendering) — verified via direct API calls only, matching this session's bar

---

### Package/bundle identifier rename — com.eziza.* → online.eziza.rider — COMPLETE 2026-07-09
User couldn't buy `eziza.com`, owns `eziza.online` instead (already the domain behind `admin@eziza.online`). App not yet published to either store, so a clean rename — no store-listing consequences. Chose `online.eziza.rider` as one consistent identifier for both platforms (previously mismatched: Android was `com.eziza.eziza_rider`, iOS was `com.eziza.ezizaRider`).
- [x] `android/app/build.gradle.kts` — `namespace`/`applicationId` → `online.eziza.rider`
- [x] Moved `MainActivity.kt` from `android/app/src/main/kotlin/com/eziza/eziza_rider/` to `.../online/eziza/rider/`, updated its `package` declaration
- [x] `ios/Runner.xcodeproj/project.pbxproj` — all 6 `PRODUCT_BUNDLE_IDENTIFIER` entries (main target ×3, RunnerTests ×3) → `online.eziza.rider(.RunnerTests)`
- [x] `ios/Runner/Info.plist` — cosmetic `CFBundleURLName` → `online.eziza.rider.paystack` (the actual registered URL *scheme*, `eziza://`, is unchanged and unrelated to the bundle ID)
- [x] 6× `userAgentPackageName: 'com.eziza.rider'` (OSM/OSRM tile-server User-Agent identification, cosmetic only) → `online.eziza.rider` across `rider_map_page.dart`, `active_delivery_page.dart`, `company_map_page.dart`, `delivery_tracking_page.dart`, `location_picker_sheet.dart`, `route_preview_map.dart`
- [x] User added the new app registrations in the Firebase console (project `eziza-rider`) themselves — `google-services.json` gained a second Android `client` entry for `online.eziza.rider` (old `com.eziza.eziza_rider` entry left in place alongside it, harmless — Gradle's google-services plugin just picks the client matching the active `applicationId`); `GoogleService-Info.plist` was replaced outright with the new iOS bundle ID + a new `GOOGLE_APP_ID`; `firebase_options.dart` updated to match both new `appId`s and the new `iosBundleId`
- [x] **Found + fixed an unrelated pre-existing bug while build-verifying**: `AndroidManifest.xml` had a literal `--` inside an XML comment (`"Call" button in the app -- contact cards`) — invalid XML, `SAXParseException: The string "--" is not permitted within comments`. This was failing `processDebugMainManifest` regardless of package name and would have blocked *any* Android Gradle build, rename or not. Fixed by rewording the comment.
- [x] `flutter analyze` clean
- [x] **Build-verified 2026-07-09**: `flutter build apk --debug` succeeds end-to-end with `applicationId = online.eziza.rider`, confirming the Firebase Android client match resolved correctly (`No matching client found` would have fired at `processDebugGoogleServices` otherwise)
- [ ] iOS side not build-verified from this environment (no Xcode/macOS toolchain run attempted here) — same fix pattern applied, should be equivalent, but worth one real `flutter build ios`/Xcode archive before assuming parity with the Android result
- [ ] Still worth cleaning up the now-orphaned `com.eziza.eziza_rider` Android client entry from the Firebase console at some point (cosmetic — not used, not blocking)

---

### Tenant API — admin onboarding surface + a real auth gap found and fixed — BUILT + live-verified 2026-07-13

ZeeFashion's integration was always the general-purpose pattern any third-party e-commerce platform would use — `create-delivery`/`get-delivery`/`cancel-delivery`/`accept-bid`/`confirm-pickup`/`confirm-receipt` all resolve a `tenant_id` from a hashed `Authorization: Bearer` key via `_shared/auth.ts::validateApiKey()`, nothing ZeeFashion-specific in any of them. What was actually missing: no way to onboard a *new* tenant except by hand (no `tenants` page existed anywhere in `eziza-admin`), and no written integration docs for a partner's engineer to follow. Both since closed — see the integration docs bullet and the `eziza-partners` self-service portal section below.

**Two real bugs found while building the admin page, both fixed:**
- [x] `tenants`/`api_keys` were never locked down the way `riders`/`companies`/`deliveries`/`customers` were in the Phase 4 column-grant fix — Supabase's default blanket grants left both fully readable/writable by the public `anon` key. Anyone could read every tenant's `api_keys` row, mint themselves a working key for **another tenant's account** by inserting their own `key_hash` against any `tenant_id` (obtainable via the same open `SELECT`), or overwrite a tenant's `webhook_url` to hijack their delivery events. Migration `20260713000000_lock_down_tenants_api_keys.sql` — `REVOKE ALL ... FROM anon, authenticated` on both tables (nothing legitimate ever touched them outside `eziza-admin`'s service-role routes and the edge functions, also service role — confirmed by grep before revoking). Live-verified: anon key now gets `42501 permission denied`; `eziza-admin`'s existing tenant billing/list routes (service role) unaffected.
- [x] `validateApiKey()` checked `api_keys.is_active` but never the parent `tenants.is_active` — deactivating a tenant only stopped their *outbound* webhooks (`dispatch-webhook` already checked `tenants.is_active` on its own), it did nothing to stop them still calling the API. Fixed by joining `tenants` and checking both; redeployed to all 6 tenant-facing functions. Live-verified: an active tenant's key returns a normal 404 (not 401) against `get-delivery`; the identical key gets rejected the instant the tenant is flagged inactive, even though the key itself is still `is_active=true`.

**New admin surface**, `eziza-admin` `/dashboard/tenants`:
- [x] `app/api/admin/tenants/route.ts` — GET (list with active/total key counts, never exposes `key_hash`), POST (create tenant + auto-issue its first API key), PATCH (name/email/webhook_url/`is_active`)
- [x] `app/api/admin/tenants/keys/route.ts` — GET (list a tenant's keys, `key_hash` never selected), POST (issue a new key), PATCH (revoke/reactivate by key id)
- [x] Raw API keys are shown exactly once, at creation, in a dedicated reveal modal with a copy button and an explicit "not stored, can't be shown again" warning — matches the "plaintext never stored" design `_shared/auth.ts` already had
- [x] `components/Sidebar.tsx` — new "Tenants" nav entry
- [x] `npm run build` and `npm run lint` clean (same pre-existing `set-state-in-effect`/`exhaustive-deps` warning pattern every other fetch-on-mount page already has, nothing new)
- [x] **Live-verified 2026-07-13** end-to-end against the real dev server and real deployed edge functions with a throwaway tenant: created via the API → issued key confirmed working against the live `get-delivery` function (404, not 401) → revoked → confirmed 401 → reactivated + issued a second key → deactivated the whole tenant → confirmed even the reactivated, still-`is_active` key is now rejected. Also used a throwaway admin account (real password-grant login, not service-role bypass) to exercise every route as an actual authenticated admin would. All throwaway rows/auth users cleaned up after.

- [x] **Integration docs** — `docs/integration-guide.html` (same design system as `support.html`/`privacy-policy.html`): getting access, auth, delivery lifecycle diagram, all 6 endpoints with real request/response shapes, all 3 webhook events with signature verification, error reference. Includes a callout clarifying "bid" (API/data-model term) = "offer" (the app's own UI term) rather than renaming the live API. Cross-linked from `docs/index.html`'s nav/footer.

### Tenant self-service portal (`eziza-partners`) — BUILT + live-verified 2026-07-13

Single login per tenant (mirrors `companies`' one-login pattern, not multi-user — see roadmap note below on why), new sibling Next.js app to `eziza-admin`, letting a tenant manage their own integration without emailing `admin@eziza.online` for every change.

- [x] Migration `20260713010000_tenants_auth_user_id.sql` — `tenants.auth_user_id`, nullable unique FK to `auth.users`, `ON DELETE SET NULL`, exactly mirroring `companies.auth_user_id`
- [x] Migration `20260713020000_tenants_self_select_policy.sql` — `tenants` had RLS enabled with **zero** policies (see security correction below); without a self-select policy, a correctly-linked tenant querying their own row via the anon key (login/auth-check, both client-side) would get nothing back. Added `tenants_self_select` (`auth_user_id = auth.uid()`), read-only, mirroring `admin_profiles`' own self-select-only pattern
- [x] Backfilled a login for ZeeFashion (`admin@zeefashion.space`) — credentials handed to the user directly. Deliberately did **not** create one for the `Eziza Direct` sentinel tenant (id `00000000-…-000000000001`) — it represents self-service in-app customers, not an external partner with an engineer who'd need portal access
- [x] `eziza-admin`'s Tenants page now also creates the login when creating a new tenant (returned once alongside the API key in the same reveal modal), and existing tenants missing one get a "Create login" button in their detail view
- [x] `lib/tenantAuth.ts::requireTenant()` — mirrors `requireAdmin()` exactly, resolves `tenants.auth_user_id = caller` (also gated on `tenants.is_active`) instead of `admin_profiles`
- [x] `/dashboard/keys` — self-service issue/revoke own API keys only (every route scopes by `caller.tenantId` server-side, never a client-supplied `tenant_id` — verified a throwaway tenant's session gets `404` touching another tenant's key, not a leak or a silent no-op)
- [x] `/dashboard/webhook` — edit own `webhook_url` only; name/email/`is_active` stay admin-managed in `eziza-admin`
- [x] `/dashboard/webhook-log` + manual replay — since webhooks aren't retried (documented limitation in the integration guide), a tenant can now see `webhook_dispatch_log` for their own deliveries and manually replay a failed one. Replay required a new edge function, `replay-webhook` (deployed, normal JWT verification since it's only ever called server-to-server with the service-role key from `eziza-partners`) — `WEBHOOK_SIGNING_SECRET` is a write-only Supabase secret with no plaintext copy anywhere in any repo, so signing had to happen there, not by reimplementing HMAC client-side in `eziza-partners`
- [x] `/dashboard/deliveries` — own delivery list, debugging only (`external_order_id`/status/timestamps), not analytics or billing
- [x] `npm run build` and `npm run lint` clean (same pre-existing warning pattern as `eziza-admin`)
- [x] **Live-verified 2026-07-13**: real ZeeFashion login (real password-grant, not service-role bypass) against every read-only route, returning real production data (their actual API key label, webhook URL, dispatch log). All mutating flows (issue/revoke key against the live API, edit webhook URL, insert-then-replay a failed webhook log entry through the real deployed `replay-webhook` function, confirmed cross-tenant isolation on both keys and replay) exercised against a separate throwaway tenant with a safe `httpbin.org` webhook target — never against ZeeFashion's real webhook. All throwaway tenants/keys/log rows/auth users cleaned up after; ZeeFashion's real webhook URL and API key confirmed untouched throughout.

**Security correction, found while building this (2026-07-13):** earlier in this session, `tenants`/`api_keys` were REVOKEd from `anon`/`authenticated` (migration `20260713000000`) on the claim that the pre-existing blanket GRANT was an active, exploitable hole. That claim was **not fully verified before being reported** — real testing done here (via `webhook_dispatch_log`, which had the identical GRANT-present/zero-RLS-policies setup and was still unfixed) showed RLS enabled with zero policies denies every command by default regardless of the underlying GRANT: anon `SELECT` returns `[]`, anon `INSERT` gets a `42501` RLS rejection — not the data leak/forgery originally described. The REVOKE itself was still reasonable (explicit denial beats an unpopulated policy set), but the severity was overstated at the time and corrected directly with the user once found. Lesson: a GRANT alone doesn't prove exploitability — check `pg_class.relrowsecurity` and actually test the anon key before calling something a live hole.

**Not yet done:**
- [x] `eziza-partners` pushed to its own GitHub repo — `https://github.com/zionnite/eziza-partners.git`
- [ ] Multi-user-per-tenant (role-split logins — engineer/support/owner) explicitly deferred per user decision 2026-07-13: speculative team-structure assumption with zero evidence any real tenant needs it yet; revisit if a partner actually asks for it
- [ ] No self-service tenant signup — the only path in is an Eziza admin manually creating the tenant + login in `eziza-admin` and relaying the generated password out-of-band. Flagged as a real bottleneck (doesn't scale, out-of-band password handoff), but may be intentional for now as a vetting gate given there's no sandbox environment — every tenant hits production immediately. Not changed pending a decision either way.

#### Password management for tenant logins — BUILT + live-verified 2026-07-13
`eziza-partners` had no way for a partner to change their admin-generated password, and no forgot-password recovery — added both, first time this pattern exists anywhere in the Next.js app family (`eziza-admin` doesn't have it either).
- [x] `/dashboard/settings` — change password while logged in (`supabase.auth.updateUser({ password })`)
- [x] `/forgot-password` — email entry, `resetPasswordForEmail`, generic "check your email" confirmation regardless of whether the address exists (not usable to probe which emails have accounts)
- [x] `/reset-password` — lands here from the emailed link; listens for the `PASSWORD_RECOVERY` auth event (supabase-js parses the recovery token from the URL automatically), then the same `updateUser({ password })` call
- [x] "Forgot password?" link added to the login page; "Settings" added to the sidebar nav
- [x] **Live-verified**: since there's no real inbox to check email delivery, verified the actual mechanics directly against a throwaway account — generated a real recovery link server-side (`auth.admin.generateLink`), consumed its `hashed_token` via `verifyOtp({ token_hash, type: 'recovery' })` (exactly what supabase-js's automatic URL-detection does when a user clicks the emailed link), updated the password through that recovery session, confirmed the old password now fails and the new one works, then did the same for the in-app change-password mechanic (update again while already signed in, confirm the newest password works). Cleaned up after.

### Self-service signup + sandbox mode — BUILT + live-verified 2026-07-14

Closes the two remaining onboarding gaps: partners couldn't create their own account (only an admin could), and there was no sandbox — every tenant hit production immediately. Both landed together since the design connects them: self-signup grants **sandbox** automatically (unvetted), admin-created tenants go straight to **live** (the admin creating one manually already is the vetting step).

**Schema** (migration `20260714000000_sandbox_mode.sql`):
- `tenants.mode` (`sandbox`|`live`, default `sandbox`) — backfilled ZeeFashion + Eziza Direct to `live`
- `deliveries.is_sandbox` — stamped at `create-delivery` time from the tenant's mode (denormalized, not derived via join — same reliability lesson as the realtime RLS denormalizations earlier in this project)
- `riders.is_sandbox` + two seed synthetic riders ("Sandbox Rider One/Two", `auth_user_id` NULL — nullable, so no real login needed for a rider that never logs in)

**The hard part — a delivery can't be "fulfilled" without a real human, so it needs a simulator**, not just a data flag. Worked out which lifecycle transitions are actually the *rider's* job vs the *tenant's own* job, and only simulated the former — everything the tenant would normally call for real (`accept-bid`, `confirm-pickup`, `confirm-receipt`) stays theirs to call, so their actual integration code gets exercised, not bypassed:
- [x] `progress-sandbox-deliveries` edge function — generates 1 fake offer on `open` sandbox deliveries after ~10s, advances `assigned → awaiting_pickup_confirm` after ~15s and `picked_up → delivered` after ~20s, writing a plausible GPS point near pickup/dropoff so `location.updated` fires too
- [x] Ticked every 15s via `pg_cron` + `pg_net` (`20260714020000_sandbox_simulator_cron.sql`) — `pg_cron` wasn't installed on this project at all (unlike ZeeFashion's, which already uses it), enabled fresh
- [x] `location.updated` couldn't reuse the existing `rider_locations` → `dispatch-location-webhook` plumbing — that table has no FK to `auth.users`, and the dispatcher's own rider lookup expects a real `auth_user_id` (sandbox riders have none by design). Dispatches this one event type directly instead, same payload/signing as the real thing, rather than bending shared infra to fit a fake rider.
- [x] `delivery.*` and `bid.placed` webhooks need **no special-casing at all** — the simulator's plain SQL INSERT/UPDATE goes through the exact same existing DB-webhook triggers a real status change or bid would, confirmed by watching them fire correctly during live verification
- [x] Real riders/companies never see sandbox deliveries — `riders_see_deliveries`/`deliveries_rider_select` RLS policies' "any open delivery" branch now requires `is_sandbox = false` (`20260714010000_hide_sandbox_from_real_riders.sql`)
- [x] Key prefixes: `eziza_test_`/`eziza_live_`, cosmetic only — `validateApiKey()` and `create-delivery` trust `tenants.mode` server-side, never the prefix. Promoting a tenant doesn't force-revoke its existing key (still works, now against real riders) — the portal recommends issuing a fresh live-prefixed key after promotion instead
- [x] `eziza-admin` Tenants page — mode badge, "Promote to Live" action (confirm dialog, since it's a real behavior change)
- [x] `eziza-partners` `/signup` — public, no approval wait. `admin.createUser(..., email_confirm:false)` creates the account+tenant+first key together server-side, then the client separately calls `auth.resend({type:'signup'})` to trigger Supabase's own confirmation email (`admin.createUser` deliberately doesn't send one) — sidesteps the chicken-and-egg problem of needing a session/token before the user has confirmed anything
- [x] Login page links to both `/signup` and `/forgot-password`; dashboard overview shows a sandbox/live badge and (in sandbox) a reminder of what it means

**Two real bugs found live-verifying, both fixed:**
- [x] **`credit_delivery_earnings()` didn't know about sandbox** — a simulated delivery reaching `confirmed` created a real `earnings_ledger` row and credited a real `wallet_balance` on the synthetic sandbox rider, fake money mixed into real reporting. Fixed (`20260714030000_exclude_sandbox_from_earnings.sql`, `SECURITY DEFINER` preserved) to skip sandbox deliveries entirely. Caught only because live-verification tried to clean up the test delivery and hit an unexpected FK from `earnings_ledger` — worth remembering that "confirmed" is the one status transition with side effects beyond the row itself.
- [x] Confirmed `auth.resend()`/`signUp()` reject `@eziza.online` test addresses ("invalid email" — likely no MX records, since that domain's only ever been used for admin placeholder accounts via `admin.createUser`, which doesn't validate deliverability). Not a bug in the app — verified `resend()` works fine against a real domain (`gmail.com`, no error) — just means real partner domains won't have this problem, a throwaway `@eziza.online` test address was the wrong choice for that specific check.

**Live-verified 2026-07-14**, real signup through real deployed infrastructure, no shortcuts: signed up a throwaway tenant → confirmed `mode='sandbox'`, key prefixed `eziza_test_` → created a real sandbox delivery via the real `create-delivery` function → confirmed a throwaway *real* rider's own RLS-filtered view of the open job board excluded it (while still showing a genuine real open delivery as a positive control) → watched the actual `pg_cron` tick generate a real offer → called the real `accept-bid`/`confirm-pickup`/`confirm-receipt` endpoints myself (playing the tenant's role, exactly as a partner's integration would) → watched the simulator advance `assigned→awaiting_pickup_confirm` and `picked_up→delivered` on schedule, unprompted → confirmed all 7 expected webhook events (`bid.placed` + 6 `delivery.*`/`location.updated`) logged in `webhook_dispatch_log`, visible through the tenant's own portal session (`/api/tenant/deliveries`, `/api/tenant/webhook-log`) → replayed one of two transient `httpbin.org` failures and confirmed it succeeded on retry → promoted the tenant to live via `eziza-admin` → confirmed the *same* old `eziza_test_`-prefixed key still worked but now created a non-sandbox delivery, visible to the real rider this time (then immediately cancelled it) → issued a fresh key post-promotion and confirmed it came back `eziza_live_`-prefixed. All throwaway tenants/keys/deliveries/riders/auth users/earnings-ledger rows cleaned up after; `ZeeFashion`/`Eziza Direct` and the two seed sandbox riders confirmed untouched throughout.

### Self-service "Request Live Access" — BUILT + live-verified 2026-07-14

Closed the last bit of the sandbox-onboarding loop: a sandbox tenant still had to email `admin@eziza.online` to ask for promotion. Now it's a button in their own dashboard.

- [x] Migration `20260714040000_tenant_live_access_request.sql` — `tenants.live_requested_at`, purely a visibility/queue marker; promotion itself is unchanged (still an admin-only `mode` PATCH)
- [x] `eziza-partners`: `POST /api/tenant/request-live` sets the timestamp (only from `sandbox`, `409` if already `live`); dashboard overview shows "Request Live Access" until requested, then "awaiting review" with the date
- [x] `eziza-admin`: Tenants list sorts sandbox-tenants-with-a-pending-request to the top and shows a red "Live requested" badge; the tenant detail view's existing sandbox banner shows the request date next to the same "Promote to Live" button (unchanged) that resolves it
- [x] **Live-verified**: real signup → real `request-live` call → confirmed it sorted first in the admin's real tenant list with the badge showing → promoted via the existing admin action → confirmed the request timestamp persists as historical info without showing as "pending" anymore (since the UI condition is `mode === 'sandbox' && live_requested_at`, and mode is now `live`). Cleaned up after.

### Sandbox blast-radius audit on the real internal app — 2026-07-14

Asked directly: does any of the sandbox work risk breaking ZeeFashion's real integration or Eziza's own internal (rider/company/customer) experience? Went through every DB-trigger-fired function that reacts to `deliveries`/`delivery_bids` changes, since those fire automatically and silently unless traced.

- [x] **Found + fixed a real regression**: `notify-new-job` (fires on every `deliveries` INSERT) had no `is_sandbox` check at all — every sandbox delivery a partner creates was push-notifying every real, available, in-range rider **and** company with "📦 New Job Available," for a job that then doesn't actually appear when they open the app (RLS filters it out). Confusing and trust-eroding for real users. One-line guard added, redeployed.
- [x] Checked `notify-bid-accepted`, `notify-delivery-update`, `notify-bid-placed`, and `dispatch-webhook`'s own embedded push logic — all four already no-op safely for sandbox data, since they all gate on a specific real identifier (`customer_id`, or a rider's/company's `auth_user_id` looked up and found null for the synthetic sandbox riders) rather than broadcasting to everyone. No fix needed.
- [x] **Found + fixed a cosmetic issue**: the two synthetic sandbox riders (pre-approved, so no pending-queue noise) were still showing up in `eziza-admin`'s real Riders list — a real admin would see two approved riders with a fake-looking phone number and zero ratings/deliveries with no explanation. Filtered out (`eq('is_sandbox', false)`).
- [x] Confirmed `tenants.mode` backfill covered **both** existing tenants correctly (`ZeeFashion` and `Eziza Direct` → `live`), so `create-delivery`'s `is_sandbox` stamp evaluates `false` for both, identical to before the column existed — verified via direct query, not assumed.
- [x] Confirmed the `credit_delivery_earnings()` sandbox-exclusion fix (found earlier, same session) means sandbox activity still can't reach `earnings_ledger`/`wallet_balance` or, by extension, any admin earnings/billing report.
- [x] **Resolved**: `eziza-admin`'s Deliveries page now has a Live/Both/Sandbox toggle (`?mode=` param on `/api/admin/deliveries`, defaults to `Live`) plus an amber "Sandbox" badge on any card shown while in `Both`. Live-verified all three modes against a real throwaway sandbox delivery mixed in with 95 real ones: `live` excluded it, `sandbox` returned only it, `both`/no param returned all 96. Cleaned up after.

Everywhere else (`tenants`/`api_keys` grants, `validateApiKey()`, RLS on `deliveries`, ZeeFashion's actual `webhook_url`/API key/tenant row) was already re-confirmed untouched throughout every live-verification pass in this session — nothing new found there.

### First real end-to-end ZeeFashion ↔ Eziza test round — several real bugs found + fixed, all live-verified — 2026-07-27

User ran an actual live test through both real apps (real merchant order, real rider bid, real buyer payment) for the first time since the integration was built — surfaced several real, previously-undetected bugs. Every fix below was live-verified against the real running apps/DB, not just reasoned about.

**Silent pickup-request failures (ZeeFashion side)**
- [x] **Found + fixed**: `store_update_tracking.dart`'s `_callEzizaGateway()` had `catch (_) {}` — any failure (network, Eziza-side error) was completely invisible; the merchant saw a green "Ready for Pickup!" success regardless of whether Eziza ever actually received the request. Confirmed live: a real merchant order's request never reached Eziza's `deliveries` table at all, with zero error shown anywhere.
- [x] Fixed: failures now flip `delivery_requests.status` to `'cancelled'` (guarded — only if still `'open'`, so a legitimate later status can't be clobbered), show a red "could not reach Eziza" snackbar, and refresh the page immediately.

**Delivery cancellation never refunded the buyer (ZeeFashion side) — the core gap this whole round was testing for**
- [x] **Confirmed real gap**: Eziza's own `cancel-delivery` correctly has no refund logic (it never holds tenant-customer money — by design). But neither `logistics-gateway`'s outbound `cancel_delivery` proxy nor its inbound `delivery.cancelled` webhook handler ever refunded anything on ZeeFashion's side, and no UI even called the outbound action. A paid, `assigned` delivery that got cancelled left the buyer's money gone with no trace.
- [x] Fixed in `logistics-gateway`'s inbound webhook handler: on `delivery.cancelled`, atomically flips `payment_status: 'paid' → 'refunded'` (idempotent — a retried webhook can't double-credit) and inserts a `wallet_transaction` (`type: 'refunded'`), letting ZeeFashion's existing `update_wallet_balance()` trigger do the crediting — same convention already used everywhere else in that codebase (`cancel_order`, dispute resolution). Refunds to wallet regardless of original payment method (wallet or card), per explicit user decision.
- [x] **Live-verified twice** on real bid-accepted-and-paid deliveries: buyer's wallet credited exactly the delivery fee both times (₦2,000 and ₦1,000), `wallet_transaction` row shape correct, `payment_status` correctly prevents double-refund.
- [x] **Investigated 2026-07-27, confirmed a different (bigger) gap, deliberately left as-is for now**: the internal (non-Eziza) rider/company delivery flow can't actually be cancelled at all once a bid is accepted and paid — `update_delivery_status()` (the only RPC that advances internal delivery status) hard-whitelists `'awaiting_pickup_confirm'`/`'picked_up'`/`'delivered'` and rejects anything else, including `'cancelled'`; no RPC, trigger, or UI anywhere sets an internal `delivery_requests` row to `'cancelled'` post-payment. So it isn't "cancels without refunding" like the Eziza case was — cancellation isn't reachable in the first place. This is a real product decision (should internal deliveries be cancellable at all, by whom, under what conditions) rather than a bug fix — deferred, not scoped or built.

**No way to retry after a cancellation (ZeeFashion side)**
- [x] **Found + fixed**: `create_delivery_request` RPC's existing-row branch only backfilled null addresses, never reset `status`/`eziza_delivery_id`/payment fields — a cancelled delivery had no path back to `'open'`. Migration `20260727000000_retry_cancelled_delivery_request.sql`: on retry of a `'cancelled'` row, resets to a clean `'open'` state and clears all dead Eziza/payment linkage.
- [x] `store_update_tracking.dart`'s "Logistics Pickup" card now shows a red "Failed"/"Cancelled" badge (distinguishing never-reached-Eziza from a genuine cancellation, via whether `eziza_delivery_id` was ever set) with a tappable "Retry"/"Retry Again" action that re-runs `_onReadyForPickup()`.
- [x] **"Start Pickup" now navigates straight to `StoreUpdateTracking`** instead of leaving the merchant on the order list to tap a second, different button (`store_order.dart`) — looks up the freshly-refreshed order from `storeOrderList` so the destination page gets the just-created tracking record, not a stale copy.

**Eziza's own uniqueness constraint blocked every retry — a systemic bug, not ZeeFashion-specific**
- [x] **Found + fixed**: `deliveries_tenant_external_idx` was a plain `UNIQUE (tenant_id, external_order_id)` with no exclusion for dead rows — once *any* delivery existed for an order, even a cancelled one, every future attempt 500'd with a duplicate-key violation, forever, for *any* tenant. Migration `20260727010000_allow_retry_after_cancelled_delivery.sql` — made it a partial unique index (`WHERE status != 'cancelled'`).

**Company-won bids never relayed the assigned rider to tenants — systemic, not ZeeFashion-specific**
- [x] **Found + fixed**: a company's bid is placed with no rider chosen (`company_dashboard_page.dart`'s `_placeBid()` sets only `company_id`); `accept-bid` assigns with `rider_id: null`. When the company later picks a specific rider (`_assignRider()`), only `rider_id` changes — `status` stays `'assigned'` — and `dispatch-webhook` only ever fired on a status change. That critical update was silently never relayed to any tenant. Fixed: `dispatch-webhook` now also fires when a company backfills the rider onto an already-`'assigned'` delivery. Live-verified: simulated the exact real scenario (rider_id null → set), confirmed the webhook fired with the correct `rider_id` and ZeeFashion's `delivery_requests.eziza_rider_id` picked it up automatically, no ZeeFashion-side changes needed.

**`product_order.delivering_status` never reflected a cancelled delivery (ZeeFashion side)**
- [x] **Found + fixed**: `sync_delivery_status_to_order()`'s `CASE` had no `'cancelled'` branch, so a cancelled delivery left the merchant's order display stuck on stale progress (e.g. "Rider Assigned") forever. Migration `20260727010000_sync_cancelled_and_retry_display_status.sql` (ZeeFashion project) adds `'cancelled' → 'Delivery Cancelled'` and `'open'` (only when the prior status was `'cancelled'`, i.e. a genuine retry) `→ 'Awaiting Rider'`. Deliberately does not touch `order_status` — that's `cancel_order()`'s domain for a full order cancellation, a bigger and different thing than a failed delivery attempt. Both transitions live-verified directly.
- [x] Both buyer-facing screens (`delivery_map_page.dart`, `track_order.dart`) also had `'open'`/`'cancelled'`/`'no_bids'` grouped into the same "waiting for rider" bucket — harmless before (cancellations used to bounce back to `'open'`), actively misleading now that `'cancelled'` is a real lasting state. Both given a proper "Delivery Cancelled" card/badge, with a refund note shown only when `payment_status == 'refunded'`.

**Misleading API error messages (Eziza side)**
- [x] **Found + fixed**: `cancel-delivery`, `accept-bid` (both its delivery and bid lookups), `confirm-pickup`, `confirm-receipt`, and `get-delivery` all did `if (!data) return json({error: 'Delivery not found'}, 404)` without checking the query's own `error` — a malformed `delivery_id` (e.g. a stray character from copying an ID out of chat/docs) fails as a Postgres invalid-UUID error, not a real zero-row lookup, but got reported as the same misleading "not found," pointing at the wrong thing to check. New shared `_shared/errors.ts::deliveryLookupFailure()` distinguishes: malformed ID → 400, genuinely missing → 404. **Caught a bug in the fix's own first version before shipping it**: `.single()` itself returns a non-null error even for the correct zero-row case (`PGRST116`) — an early version treated any error as a 500, which would have turned every genuine "not found" into a confusing raw PostgREST 500. Corrected and both paths live-verified against the real deployed functions.

**Raw technical errors shown to users (Eziza side)**
- [x] New `lib/utils/error_messages.dart::humanizeError()` — network/TLS/socket errors → "Network issue — check your connection and try again"; `AuthException` → shown as-is (Supabase Auth already writes these for end users); `PostgrestException` → generalized (can leak schema detail); bare `throw Exception('...')` (this codebase's existing convention for deliberate short messages like "Not logged in") → shown as-is. Applied to `company_dashboard_page.dart` (offer submission — the one that surfaced a raw `SSLV3_ALERT_BAD_RECORD_MAC` to the user), `rider_map_page.dart` (OTP send), `company_registration_page.dart`, `change_password_page.dart`, `wallet_page.dart`.

**Rating prompts: one double-fired, the other never showed at all (Eziza side, `rider_map_page.dart`)**
- [x] **Found + fixed — "Rate Sender" firing twice**: a race between the Realtime subscription and the 5-second handoff poll — the poll only checked its `_waitingHandoff` guard *before* its network await, not after, so if Realtime already handled the `picked_up` transition while the poll's request was in flight, both called `_advanceToDropoff()` independently. Fixed with a post-await re-check plus a `_advancingToDropoff` guard on the function itself (same pattern as the existing `_closing` guard on `_closeMap()`).
- [x] **Found + fixed — "Rate Receiver" never showing**: `_maybeShowRateCustomerSheet()` called `showRatingSheet()` (a `Future<void>` meant to resolve on dismiss) without `await`ing it. `_closeMap()`'s own comment says it needs to "wait out the rate-receiver prompt... before we pop this page away," but since the inner call wasn't truly awaited, the very next line (`Get.back(result: 'confirmed')`) popped the page out from under the sheet before it could ever render. Fixed by adding the missing `await`.
- Neither bug was related to company-vs-individual rider status, despite that being the initial suspicion — confirmed no such branching exists anywhere in the trigger path, and `rider_auth_user_id` (the column the RLS/Realtime authorization depends on) was independently confirmed correctly populated for company-assigned riders throughout.

### Stale pending offers on both rider-side and company-side job boards — found + fixed, live-verified 2026-08-10

User reported two related bugs: (1) a company's "Pending Offers" list kept showing an offer as pending even after the customer booked a different delivery partner (External Carrier) for that delivery; (2) an individual rider's job board kept showing "Make an Offer"/"Place Offer" even after that rider had already placed an offer on the delivery.

**Bug #1 — stale `delivery_bids.status` after external-carrier booking**
- [x] **Root cause**: `pay_and_accept_delivery_bid` already rejects sibling pending bids when an *internal* bid wins (`UPDATE delivery_bids SET status='rejected' WHERE delivery_id=... AND status='pending'`), but `finalize_book_external_carrier`/`finalize_book_external_carrier_for_tenant` (the External Carrier booking path) never touched `delivery_bids` at all — a bid placed before the customer booked an external carrier was left stuck at `'pending'` forever.
- [x] Fixed generically rather than patching every RPC individually: migration `20260810020000_reject_stale_bids_on_assignment.sql` adds `trg_reject_pending_bids_on_delivery_left_open`, an `AFTER UPDATE ON deliveries` trigger (`WHEN OLD.status='open' AND NEW.status IS DISTINCT FROM 'open'`) that rejects any still-pending `delivery_bids` for that delivery — covers internal-bid-accept, both external-carrier booking paths, and cancellation, plus any future path that moves a delivery off `'open'`.
- [x] Included a one-off backfill for bids already stuck stale from earlier live testing that day — confirmed exactly 2 rows fixed (one individual-rider offer, one company offer, both on the same externally-booked delivery).

**Bug #2 — job board had zero awareness of the rider's own bids**
- [x] **Two separate implementations of the job board exist** — `job_board_page.dart`/`DeliveryController` (GetX-based) and `RiderDashboardPage._deliveryCard` (the app's actual home screen, plain `State`-based, entirely separate open-deliveries fetch/render logic). First fix pass only touched the former; user re-tested and the bug was still live because the real screen in use is the latter. Both were fixed:
  - `DeliveryController`: added `myPendingBidDeliveryIds`, loaded via `_loadMyBids()` alongside `_loadOpen()`/`_loadActive()`, refreshed after a successful `placeBid()` and via a realtime subscription on `delivery_bids` filtered by `rider_id`. `job_board_page.dart`'s `_DeliveryCard` shows an "Offer Sent" chip instead of the "Place Offer" button when the rider already has a pending bid on that delivery.
  - `RiderDashboardPage`: `_load()` now also fetches this rider's pending `delivery_bids` into `_myBidDeliveryIds`; the offer-submit handler updates it locally right after a successful upsert; `_deliveryCard` shows "Offer Sent — Tap to Edit" instead of "Make an Offer" (still tappable — the backend already upserts on `(delivery_id, rider_id)`, so editing an existing offer works as-is).
- [x] **Found and fixed a reactivity bug along the way**: `myPendingBidDeliveryIds` was first written as an `RxSet<String>`, whose `.value` setter the analyzer flagged as a protected-member misuse — a sign this GetX version's `RxSet` doesn't carry the same `Obx` dependency-tracking as `RxList`. Directly confirmed via DB query that the underlying data was correct (pending bid rows existed for open deliveries) before concluding it was a pure client-side rendering bug. Switched to a plain `RxList<String>`, matching `openDeliveries`' already-proven-working pattern in the same file.

### Tenant self-service Paystack top-up + admin visibility fix — BUILT + live-verified 2026-08-10

User reported two related gaps: a tenant's "top-up requested" flag wasn't visible anywhere an admin would actually look, and tenants had no way to actually pay — only to flag "please credit me" for an admin to act on manually.

**Admin visibility gap**
- [x] **Root cause**: the DB write itself worked fine (confirmed directly — a real tenant's `topup_requested_at`/`topup_requested_amount` were set correctly), but `eziza-admin` only ever surfaced it as a small amber badge on that tenant's own card inside the Tenants list. No count anywhere else in the console, and the separate "Approvals" page (riders/companies only) is where an admin would naturally look for a pending-action queue.
- [x] Fixed: `Sidebar.tsx` now fetches the tenant list once and shows a numeric badge on the **Tenants** nav item for any tenant with a pending top-up or live-access request — visible from any page in the console, not just when happening to open Tenants.

**Real Paystack top-up (`eziza-partners`)**
- [x] New Eziza edge function `tenant-paystack-initialize` — tenant-facing twin of the existing customer-facing `paystack-initialize`. Verifies the tenant's own Supabase session JWT (forwarded as-is from `eziza-partners`, not an API key), then initializes a Paystack transaction server-side. `PAYSTACK_SECRET_KEY` stays in the Eziza project only — never duplicated into `eziza-partners`' own env.
- [x] `paystack-webhook` extended with a `purpose === 'tenant_topup'` branch — credits `tenant_wallet_transactions` (same idempotent-on-`reference` shape as the existing customer `wallet_topup` branch; the table already had a unique index on `reference` and a crediting trigger from the External Carriers work, both reused as-is) and clears any pending manual top-up request, since a real payment landed.
- [x] `eziza-partners` dashboard: "Pay with Paystack" (amount + button → redirects to Paystack's hosted checkout) is now the primary action. The old manual "Request Top-Up" flow is kept, collapsed behind a "paid another way (bank transfer, etc.)" link — not removed, since some tenants may still pay out-of-band. New `/dashboard/topup/callback` page polls `/api/tenant/me` after the Paystack redirect until the balance updates (crediting happens via the webhook server-to-server, not tied to the redirect itself).
- [x] **Live-verified against the real deployed functions** with a throwaway tenant + auth user (no real tenant's login touched): `tenant-paystack-initialize` returned a real `checkout.paystack.com` URL; a garbage token correctly 401'd at the gateway, a negative amount correctly rejected by the function's own validation. Couldn't forge a valid Paystack webhook signature (no access to the secret key value), so verified the webhook's DB-level crediting path directly instead — same insert shape the webhook code produces: balance credited correctly, inserting the same `reference` twice correctly failed as a harmless duplicate-key error (no double-credit), and the manual-request flag cleared. All throwaway rows (tenant, wallet transaction, auth user) deleted after.

### Payouts page — rider/company payout requests had NO admin UI at all — BUILT + live-verified 2026-08-10

User asked whether rider withdrawal requests show up anywhere on the admin side. They didn't — `eziza-admin` had zero code referencing payouts at all, not even a buried badge like the tenant top-up gap fixed earlier the same day. Checking the DB directly found 3 real pending requests that had been completely invisible: two rider requests (₦4,500 and ₦23,703, the ₦23,703 one sitting since 2026-07-07) and one company request (₦111,447.90, also since 2026-07-07).

- [x] New RPCs (`eziza_rider` migration `20260810030000_admin_process_payout_requests.sql`) — `admin_process_rider_payout`/`admin_process_company_payout` atomically debit the requester's `wallet_balance` and flip the request to `'paid'` in one transaction (row-locked against double-processing via `FOR UPDATE`), **hard-blocked if the current balance can't cover the requested amount** rather than silently pushing it negative. `'rejected'` just closes the request out, no wallet touch. Companies also get `paid_out` incremented (existing column, riders don't have an equivalent).
- [x] That balance guard mattered immediately in practice: of the 3 real pending requests, only the ₦4,500 one (exact balance match) can currently be marked paid as-is — the company's balance has drifted to ₦13,500 against its ₦111,447.90 request, and the other rider's balance is now ₦0 against its ₦23,703 request. Both correctly block instead of corrupting the balance; whoever processes these will need to resolve the mismatch first (partial payment isn't supported by this flow).
- [x] New `eziza-admin` **Payouts** page (`/dashboard/payouts`) — merges `rider_payout_requests` + `company_payout_requests` into one feed, pending requests shown first with "Mark Paid"/"Reject" actions (a confirm dialog on Mark Paid, since it debits immediately), bank details shown per request, current balance shown next to the requested amount with a red warning when it's short. Processed history collapsed behind a toggle. Sidebar nav gets a pending-count badge, same pattern as Tenants' badge from earlier in the day — the `pendingCounts` state in `Sidebar.tsx` was generalized from a single tenant-only value to a `Record<href, count>` map to support this cleanly.
- [x] **Live-verified against the real deployed route and RPCs** with a throwaway rider + 3 throwaway requests: sufficient-balance paid correctly debited and marked paid, rejected correctly left the wallet untouched, insufficient-balance correctly blocked with the exact current/requested figures in the error, re-processing an already-paid request correctly rejected. The 3 real pending requests were only ever read via the API, never acted on. All throwaway rows cleaned up after.

## Key Credentials & URLs

| Item | Value |
|---|---|
| Eziza Supabase project | `nvwpsccleewgirlwokys.supabase.co` |
| Eziza DB pooler | `postgresql://postgres.nvwpsccleewgirlwokys:V3JYMT0xTUTUosKM@aws-0-eu-west-1.pooler.supabase.com:5432/postgres` |
| Eziza GitHub | `https://github.com/zionnite/eziza.git` |
| eziza-admin GitHub | `https://github.com/zionnite/eziza-admin.git` |
| eziza-partners GitHub | `https://github.com/zionnite/eziza-partners.git` |
| Sandbox simulator cron job | `progress-sandbox-deliveries-tick`, every 15s (`SELECT * FROM cron.job`) |
| Termii SMS | Abandoned — Termii started requiring BPP/CPN business licensing disproportionate to basic OTP use. Replaced with Sendchamp 2026-07-28, see below. |
| Sendchamp SMS | **Abandoned 2026-07-30** — same licensing/KYC wall as Termii, no path to a working account. Replaced entirely with the sender/recipient-relayed handoff code below; `confirm-delivery-otp` no longer calls any SMS provider. |

## Delivery hand-off code — SMS removed entirely — BUILT + live-verified 2026-07-30

Sendchamp joined Termii on the same wall (SMS licensing/KYC neither could clear), so the OTP-by-SMS design for confirming physical receipt was replaced outright rather than chasing a third provider. Scope check done first: this only ever applied to Eziza's own native "Send a Package" flow (`send_package_page.dart`, rider-driven confirm via `confirm-delivery-otp`) — tenant-routed deliveries (e.g. ZeeFashion) were already confirmed a completely different way, a plain tap-to-confirm in the tenant's own app via the `confirm-receipt` tenant action, no OTP involved at all. Nothing on the ZeeFashion side needed to change.

**Design, agreed with the user directly** (busy senders can't be expected to be watching the app right at hand-off time; a recipient who already has the app shouldn't have to wait on the sender to relay anything):
1. The code is generated once, **at delivery creation**, not when the rider marks it delivered.
2. It's visible in plain text to the **sender**, from creation onward, on their own delivery screen — and separately to a **matched/claimed recipient** (same phone-match/claim logic the Incoming tab already used) on theirs. Either can also directly tap "Confirm Receipt" themselves via the existing recipient RLS policies — the code is a convenience alongside that, not a replacement for it.
3. The **rider never sees the code** at all, under any circumstance, including on failure — preserving the one property that actually matters (proof someone legitimate was told the code).

- [x] Migration `20260730040000_handoff_code_no_sms.sql`: `delivery_otps` gets a plaintext `code` column (previously stored only a SHA-256 hash) and a `locked_until` column; dropped `otp_hash`/`expires_at` entirely — a code generated hours or days before drop-off can't sensibly carry a 10-minute expiry anymore. New trigger `deliveries_set_handoff_code` (mirrors the existing `deliveries_set_tracking_code` pattern) fires `AFTER INSERT ON deliveries`, generating the code immediately. New RLS: `sender_can_read_handoff_code` / `recipient_can_read_handoff_code`, deliberately reusing the exact same `normalize_phone`/`recipient_auth_id` predicate the deliveries table's own recipient policies already use, rather than inventing a second definition of "who counts as the recipient" to keep in sync by hand.
- [x] **Kept `delivery_otps` as a genuinely separate table on purpose, not a column on `deliveries`** — the rider's own `deliveries` query is a plain `select()` (all columns), so a code stored directly on that row would have been visible to the rider regardless of what the Flutter UI chose to display, defeating the entire point. Confirmed no policy on `delivery_otps` grants the rider (or anyone but sender/recipient) any access at all.
- [x] **Real bug caught by testing before it shipped**: the migration's backfill only inserted a code for deliveries with *no* existing `delivery_otps` row — 36 deliveries that already had a row from the old SMS-request flow were silently left with `code = NULL` once `otp_hash` was dropped. Caught by querying for `code IS NULL AND verified_at IS NULL` after applying, fixed with a follow-up migration (`20260730040001_backfill_missing_handoff_codes.sql`), re-verified zero rows left.
- [x] `confirm-delivery-otp` rewritten: the `send` action (and `sendSms()`, `normalisePhone()`, `maskPhone()`, the `_sms_debug_TEMP` diagnostics) removed entirely — there's nothing left to send, the code already exists. `verify` now compares against `delivery_otps.code` directly. Lockout softened from "3 wrong attempts, dead end, must resend" (meaningless once there's no way to get a new code) to a 2-minute cooldown that resets attempts and allows retrying, since it's the same one code for the whole delivery.
- [x] `rider_map_page.dart` / `_OtpSheet`: removed `maskedPhone`, `devOtp`, the resend button and its 30s/60s cooldown timers — the sheet is now just "enter the 6-digit code the recipient gives you," nothing else. This also closes the real gap the old dev-OTP fallback had: when SMS failed, the code was returned to the **rider's own** app response and shown in an amber banner — the rider could see the code they were supposed to be asking someone else for.
- [x] `customer_delivery_detail_page.dart`: new "Delivery Code" card (own `_sectionCard`, copy-to-clipboard, no new package dependency — matches the tracking-code copy pattern already in this file rather than pulling in `share_plus`), shown to both sender and recipient views whenever a code is fetched and not yet verified; cleared client-side the moment Realtime reports the delivery `confirmed` or `cancelled`, so the card doesn't linger once there's nothing left to hand off. Deliberately worded and styled distinctly from the existing tracking-code chip in the header — the two serve different purposes (finding/claiming a delivery vs. proving receipt at the door) and showing them identically would invite mixing them up.
- [x] `flutter analyze` clean on both edited files.
- [x] **Live-verified end-to-end against the real deployed function** with a throwaway rider (real auth user + `riders` row) and two throwaway deliveries: confirmed a delivery's code exists from the moment it's inserted (checked inside a rolled-back transaction, before any status change); confirmed RLS directly via role/JWT impersonation — the real sender sees the code, an unrelated authenticated user and `anon` both get zero rows; called the live `confirm-delivery-otp` with a wrong code (correct "N attempts left" error), then the right code (`{"ok":true}`, delivery flipped to `confirmed`, re-verify correctly rejected as "already confirmed"); separately drove a second throwaway delivery through 3 wrong attempts and confirmed the lockout message with a live countdown. **Found and cleaned up one real side effect while tearing down**: the confirmed throwaway delivery had triggered a genuine `earnings_ledger` row (₦0, since no `agreed_price` was ever set on it) — same "`confirmed` is the one status transition with side effects beyond the row itself" lesson noted earlier in this file. Deleted the ledger row before the delivery/rider/auth user, all four confirmed gone afterward.

## Tracking Code Format
- 6 uppercase alphanumeric chars
- Character set: `ABCDEFGHJKMNPQRSTUVWXYZ23456789` (no O, 0, I, 1, L)
- ~1 billion possible codes — no collisions at any realistic scale
- Sender taps code in delivery header to copy → shares via WhatsApp/SMS
- Recipient enters code in "Track a Package" → auto-claimed in one step, no confirm button
