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
- [x] `rider_map_page.dart` — live GPS navigation during active delivery. OSRM route polyline, ETA, pickup (gold) and dropoff (purple) markers, Confirm Pickup → Confirm Delivery flow. Updates foreground notification text. Upserts rider GPS to `rider_locations`. Auto-closes when customer confirms receipt
- [x] `job_board_page.dart` — open deliveries within rider's coverage area; bid submission sheet
- [x] `active_delivery_page.dart` — full delivery detail + status stepper + action buttons
- [x] `earnings_page.dart` — wallet balance, completed deliveries list, Request Payout flow

#### Company Flow
- [x] `company_registration_page.dart` — 3-level location picker (State → City → Area) from admin-managed `locations` table via `CoverageLocationService`. Bank picker via `BankService`
- [x] `company_dashboard_page.dart` — 3 tabs: Deliveries (bid placement, rider assignment, realtime), Riders (manage fleet, invite riders), Earnings (payout requests). Realtime updates throughout
- [x] `company_map_page.dart` — Fleet overview map. All company riders shown simultaneously with live GPS dots, color-coded OSRM route polylines, destination markers. "Fleet Map" button in Riders tab. Online/Stale/Offline status chips in bottom panel. 30-second refresh timer

#### Customer Flow
- [x] `home_page.dart` "Send & Receive Packages" → saves customer role to Supabase metadata → Obx routing navigates to CustomerDashboardPage
- [x] `customer_dashboard_page.dart` — full dashboard: stats row (Awaiting Bid / In Transit / Completed), active deliveries, history, FAB → SendPackagePage
- [x] `send_package_page.dart` — delivery request form with map-based pickup and dropoff selection. Both addresses picked via `LocationPickerSheet` (drag-to-pin). Stores `pickup_lat/lng`, `dropoff_lat/lng` + address strings on `deliveries` row
- [x] `location_picker_sheet.dart` — reusable bottom sheet map picker. `FlutterMap` drag-to-pin, GPS auto-fill, 600ms reverse geocode debounce (Nominatim), 1500ms forward geocode debounce on state/city fields, `_suppressListeners` flag prevents feedback loop, expand/collapse map, zoom +/-, landmarks chips. Returns `LocationResult({address, lat, lng})`
- [x] `my_deliveries_page.dart` — list of customer's deliveries with status chips, pull-to-refresh, FAB → new request
- [x] `customer_delivery_detail_page.dart` — bid list (rider + company bids), accept bid dialog (auto-rejects others), progress timeline, "Confirm Receipt" when status=delivered, "Track Live" button for assigned/picked_up/delivered
- [x] `delivery_tracking_page.dart` — live map tracking. Two-step rider_id → auth_user_id → rider_locations lookup. Realtime GPS updates, OSRM ETA, pulsing gold rider dot, "Confirm Receipt" button, "Showing last known location" banner when stale

#### Services / Models
- [x] `lib/models/location.dart` — Location model (State/City/Area)
- [x] `lib/services/coverage_location_service.dart` — fetches admin-managed locations with in-memory cache
- [x] `lib/services/location_service.dart` — GPS tracking (existing, do not rename)
- [x] `lib/services/rider_location_task.dart` — foreground task callback (existing)

#### Database Migrations (applied to Eziza Supabase)
- [x] `20260702000001_locations.sql` — `locations` table + `coverage_area_ids` on companies
- [x] `20260702000002_company_dashboard.sql` — `company_id` on `delivery_bids`, `company_payout_requests` table, company RLS
- [x] `20260702000003_customer_flow.sql` — Eziza Direct tenant, `customer_id` on deliveries, customer RLS
- [x] `20260704000003_companies_status.sql` — `ALTER TABLE companies ADD COLUMN IF NOT EXISTS status` (table existed so CREATE TABLE IF NOT EXISTS skipped it)
- [x] `20260701000005_deliveries_latlng.sql` — adds `pickup_lat`, `pickup_lng`, `dropoff_lat`, `dropoff_lng` to `deliveries`

#### Push Notifications
- [x] `send-notification` edge function — FCM HTTP v1 API with JWT signing. Updated to accept `user_id` (looks up FCM token from `device_tokens`) OR raw `token` — matches ZeeFashion pattern
- [x] `notify-new-job` edge function — rewritten. Dual geographic matching: state match (`coverage_states` contains `pickup_state`) OR GPS radius ≤ 50 km. Riders with no `rider_locations` row are skipped (no benefit of the doubt). Companies matched by `companies.state`. Passes `user_id` to `send-notification`
- [x] `dispatch-webhook` edge function — updated to notify rider (bid accepted), customer (assigned / picked_up / delivered), company (bid accepted) on delivery status change
- [x] `notify-bid-placed` edge function — notifies customer when a bid is placed on their delivery (DB webhook on `delivery_bids` INSERT — **configure in Supabase Dashboard**)
- [x] `device_tokens` table + migration — universal FCM token store for companies/customers (riders also keep `riders.fcm_token` for `notify-new-job` backward compat)
- [x] `fcm_service.dart` — saves token to `device_tokens` for all user roles; expanded tap routing: `bid_placed` → CustomerDeliveryDetailPage, `delivery_update` → DeliveryTrackingPage, `bid_accepted`/`new_job` → refresh rider jobs
- [x] `auth_controller.dart` — FCM now initializes for all logged-in users (not just approved riders)

#### GPS / Location Fixes
- [x] **FK constraint bug fixed** — `rider_locations.rider_id` had FK pointing to `riders.id` (row UUID) but code inserts `auth.uid()`. Every upsert silently failed. Migration `20260704000004_fix_rider_locations_fk.sql` drops the wrong FK and dead `riders_own_location` RLS policy
- [x] **`rider_dashboard_page.dart` — `_withinRadius`** — checks `coverage_states` state match first; falls back to GPS radius; returns `false` when no GPS fix (no benefit of the doubt). First GPS fix triggers `_reloadOpenDeliveries()` so job board populates correctly
- [x] **`rider_dashboard_page.dart` — `_stopLocationBroadcast`** — now deletes rider's `rider_locations` row after stopping GPS service. Ensures no stale location data remains in DB when rider goes offline or all deliveries are confirmed
- [x] **`delivery_tracking_page.dart`** — on `confirmed` status event, clears `_riderLocation`, `_locationIsLive`, `_routePoints`, and `_etaSeconds`. Rider pin disappears from customer map immediately on confirmation

#### Stuck Card Fix (customer confirms — card stays)
- [x] **`rider_dashboard_page.dart` — `_confirmedPollTimer`** — polls DB every 12 s for deliveries whose status has become `confirmed` (fallback for missed Realtime events). Immediate check on start (`_startConfirmedPoll`) resolves the race where customer confirms before Realtime fires. Poll cancels itself when no more `delivered`-status deliveries remain

#### `pickup_state` + Geographic Matching
- [x] **Migration `20260704000005_pickup_state.sql`** — adds `pickup_state TEXT` column to `deliveries`
- [x] **`location_picker_sheet.dart`** — `LocationResult` typedef extended to include `state` field; `_confirm()` returns state extracted from Nominatim reverse geocode
- [x] **`send_package_page.dart`** — captures `result.state` from picker and writes `pickup_state` on delivery insert

#### Packages added to `pubspec.yaml`
- [x] `http: ^1.2.2` — OSRM routing + Nominatim geocoding API calls
- [x] `url_launcher: ^6.3.1` — `tel:` URIs for call buttons in map pages

---

## 🚧 Pending

### Infrastructure
- [ ] **iOS APNs key** — upload APNs Auth Key to Firebase Console (manual step)
- [x] **Supabase DB webhook: `notify-bid-placed`** — `on_bid_insert_notify_customer` trigger on `delivery_bids` INSERT, deployed via migration `20260704000002`
- [ ] **Custom domain for API** — replace raw Supabase URL with `api.eziza.com` (Cloudflare proxy or Supabase Pro custom domain). Do before onboarding paying tenants
- [ ] **Admin dashboard** — approve riders/companies, manage `locations` table, view all deliveries, manage payouts
- [ ] **Shipbubble fallback** — when no rider bids within window, fall back to external carrier

### OTP Delivery Confirmation (Designed — not yet built)

**Design decision:** OTP is the universal confirmation mechanism across ALL Eziza tenants.
Tenant in-app confirmation (e.g. ZeeFashion buyer tapping "I received my package") is an
additional path on top — not a replacement.

**Role mapping (ZeeFashion context):**
| Eziza role | ZeeFashion equivalent |
|---|---|
| Sender | Merchant (has the package, hands it to rider) |
| Recipient | Buyer (placed the order, receives package) |

**Confirm Handoff:**
- Rider arrives at merchant (pickup) → marks `awaiting_pickup_confirm` in Eziza rider app
- **Merchant confirms handoff in ZeeFashion** (existing merchant tracking UI — already built)
- ZeeFashion calls `logistics-gateway` → advances Eziza delivery to `picked_up`

**Confirm Receipt — universal OTP flow:**
- Rider arrives at recipient address → taps "Delivered" in Eziza rider app
- Eziza edge function generates OTP + sends SMS to recipient's phone number
- Rider asks recipient for OTP → enters it in rider app → delivery marked `confirmed`
- Works for every tenant regardless of whether recipient has any app installed

**Confirm Receipt — tenant in-app (additional layer):**
- Simultaneously, `dispatch-webhook` fires to tenant (e.g. ZeeFashion)
- ZeeFashion sets `delivering_status = 'Awaiting Confirmation'` → buyer sees confirm button
- Buyer confirms in ZeeFashion → ZeeFashion calls back to Eziza → `confirmed`
- Whichever path fires first (OTP or in-app) closes the delivery

**Build items:**
- [ ] `confirm-delivery-otp` Eziza edge function — generates OTP, sends SMS to recipient phone
- [ ] OTP entry screen in Eziza rider app — rider enters code received from recipient
- [ ] Wire ZeeFashion merchant handoff confirm → Eziza `picked_up` (in `logistics-gateway` + `order_controller.dart`)
- [ ] Pass buyer phone number when ZeeFashion creates Eziza delivery request (`logistics-gateway`)
- [ ] Extend `dispatch-webhook` — on `delivered` status, fire tenant webhook so buyer sees confirm prompt
- [ ] ZeeFashion `packageReceived()` calls back to Eziza → `confirmed` (`order_controller.dart`)

### External Carriers / Third-Party Logistics (Designed — not yet built)

**Design decision:** External providers (GIG Logistics, DHL, Redstar, etc.) are NOT part of
the bidding system. They appear as a separate "External Carriers" section alongside bids.
Shipbubble is the recommended single integration — it aggregates multiple Nigerian carriers
under one API, giving access to GIG, DHL, Redstar, etc. without separate integrations.

**Two sub-types of external carriers:**
- **API-backed** (Shipbubble/Sendbox) — instant quotes fetched live when delivery is created
- **Manual rate card** — admin configures fixed state-to-state prices in admin panel; admin
  physically books with the carrier when customer selects; admin updates tracking manually

**What the customer sees (delivery detail page):**
```
┌─ Eziza Riders (2 bids) ────────────────┐
│  John Doe · Motorcycle    ₦1,200  Accept│
│  QuickRun Ltd · Van       ₦1,800  Accept│
└─────────────────────────────────────────┘
┌─ External Carriers ────────────────────┐
│  GIG Logistics    ₦3,450   2-3 days    │
│  DHL Express      ₦6,200   1 day       │
│  Redstar          ₦2,900   3-5 days    │
└─────────────────────────────────────────┘
```

**DB tables needed:**
- `external_carriers` — name, logo, api_type (shipbubble | manual), api_key, is_active
- `external_carrier_rates` — carrier_id, from_state, to_state, price, days (manual type only)
- `external_carrier_bookings` — delivery_id, carrier_id, carrier_ref, status, tracking_url

**Build items:**
- [ ] `external_carriers` + `external_carrier_rates` + `external_carrier_bookings` DB migration
- [ ] Shipbubble API integration — fetch live quotes when delivery request is created
- [ ] Admin panel — manage external carriers + manual rate cards
- [ ] Customer delivery detail page — "External Carriers" section alongside bids
- [ ] Booking flow — when customer selects external carrier, book via Shipbubble API or notify admin
- [ ] Tracking poll — sync external carrier tracking status into Eziza delivery status

---

### Monetisation Strategy (Designed — not yet built)

**Why Eziza can markup external carriers and stay cheaper than retail:**
Shipbubble negotiates wholesale/volume rates below what customers pay walking in.
Eziza marks up 10-15% and the customer still saves vs. going direct.

```
Example Lagos → Abuja:
  GIG retail (customer walks in)  ₦4,500
  Shipbubble rate to Eziza        ₦3,000
  Eziza shows customer            ₦3,450  (15% markup)
  Eziza pockets                     ₦450
  Customer saves vs. retail        ₦1,050
```

**Revenue streams:**

1. **Commission on Eziza riders/companies** — 10-15% of agreed delivery price.
   Deducted at payment time; rider never touches the commission amount.

2. **Markup on external carriers** — 10-15% on top of Shipbubble wholesale rate.
   Customer still pays less than retail. Eziza pockets the spread.

3. **B2B tenant fee** — Monthly API access fee for tenants (ZeeFashion, others).
   Or per-delivery fee (₦50-100). Volume tiers: more deliveries = lower per-delivery cost.

4. **Package insurance upsell** (later) — Optional at checkout (₦150-500).
   Partner with insurer, split the premium.

**Natural pricing balance:**
- Same-city / short distance → Eziza rider wins (cheaper, faster) → commission model
- Interstate / no rider bids → External carrier wins → markup model
- Either way Eziza earns. Competition between the two keeps prices fair for customers.

**DB addition needed:**
- `delivery_fee_breakdown` column (jsonb) on `deliveries` table:
  `{ base_amount, platform_fee, total_charged, fee_type: 'commission'|'markup'|'tenant_fee' }`

**Build items:**
- [ ] Commission deduction wired into `pay_and_accept_delivery_bid` RPC
- [ ] Markup applied when fetching/displaying external carrier quotes
- [ ] `delivery_fee_breakdown` stored on every completed booking
- [ ] Earnings dashboard in admin panel — revenue per stream (commission / markup / tenant fees)
- [ ] Tenant billing — monthly invoice generation or per-delivery ledger

---

## When to Switch Back to ZeeFashion (Android Studio)
Return to Android Studio + ZeeFashion when working on:
- Enabling `FeatureFlags.eziza = true` and testing the end-to-end flow with a real rider bid
- Shipbubble fallback integration (ZeeFashion Flutter + `logistics-gateway` edge function)
- Measurements feature (`lib/pages/setting/` + profile DB columns)
- Cashback system (wallet page + `cashback_balance` table)
- Any ZeeFashion bug fixes that come up during Eziza rider app testing
