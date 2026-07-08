-- Same vulnerability class just found and fixed on customers: Supabase's
-- default privileges grant `authenticated` a blanket table-level UPDATE
-- (all columns) on every table, which silently coexists with any RLS
-- UPDATE policy scoping rows to "own row" — meaning riders/companies could
-- currently PATCH their own wallet_balance, rating_avg, rating_count,
-- is_approved, or status directly, bypassing every trigger/admin-approval
-- flow that's supposed to be the only thing moving those fields. Pre-
-- existing gap, not introduced by anything built this session — just
-- surfaced by testing the same pattern on customers.pin.
--
-- Does NOT affect the ZeeFashion (or any tenant) integration — every
-- tenant-facing edge function (create-delivery, accept-bid, confirm-pickup,
-- confirm-receipt, dispatch-webhook, and all notify-* functions) uses
-- SUPABASE_SERVICE_ROLE_KEY exclusively, which bypasses RLS and every
-- GRANT/REVOKE restriction below entirely. This only restricts the
-- `authenticated` role — i.e. the app's own logged-in users.

-- riders: precise allowlist built from every from('riders').update(...)
-- call site in the actual Flutter app (full_name, phone, email, vehicle_*,
-- coverage_states, bank/account fields at profile-edit; is_available at
-- the online/offline toggle; fcm_token at device registration; gov_id_url/
-- selfie_url at rider application). Everything else — is_approved,
-- rating_avg, rating_count, total_deliveries, wallet_balance, status — is
-- server-managed only (admin approval, rating/earnings triggers).
REVOKE UPDATE ON public.riders FROM authenticated;
GRANT UPDATE (
  full_name, phone, email, vehicle_type, vehicle_plate, coverage_states,
  bank_name, account_number, account_name, is_available, fcm_token,
  gov_id_url, selfie_url
) ON public.riders TO authenticated;

-- companies: no app code currently updates a company row at all post-
-- registration (Phase 5 will add real profile editing) — revoke the
-- blanket grant with nothing re-granted yet, closing the gap with zero
-- risk of breaking existing functionality.
REVOKE UPDATE ON public.companies FROM authenticated;

-- deliveries: blocklist, not allowlist — this table has a large,
-- well-established direct-write surface built up over the whole project
-- (status transitions, timestamps, GPS fields, rider_id assignment) and a
-- full rewrite risks breaking something real. Only the financial fields
-- need protecting; everything else already gets correctly scoped by the
-- existing per-role RLS UPDATE policies.
REVOKE UPDATE (
  agreed_price, platform_fee, payment_status, payment_source, payment_ref,
  delivery_fee_breakdown
) ON public.deliveries FROM authenticated;
