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

### ZeeFashion ↔ Eziza Integration (Designed — not yet wired)
- [ ] Pass buyer phone number when ZeeFashion creates Eziza delivery (`logistics-gateway`)
- [ ] Wire ZeeFashion merchant handoff confirm → Eziza `picked_up`
- [ ] Extend `dispatch-webhook` — on `delivered`, fire tenant webhook so buyer sees confirm prompt
- [ ] ZeeFashion `packageReceived()` calls back to Eziza → `confirmed`

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
