-- Bank code was already being selected via a bank picker at rider
-- registration (rider_application_page.dart's Step 3), but riders had no
-- bank_code column to persist it to -- silently dropped since day one, so
-- admin payouts (Paystack transfer, which requires bank_code) could never
-- resolve a rider's actual bank. Add the column and extend the riders
-- UPDATE grant (see 20260712070000_lock_down_sensitive_columns.sql) to
-- include it, matching how companies already capture bank_code.
ALTER TABLE public.riders ADD COLUMN IF NOT EXISTS bank_code text;

REVOKE UPDATE ON public.riders FROM authenticated;
GRANT UPDATE (
  full_name, phone, email, vehicle_type, vehicle_plate, coverage_states,
  bank_name, bank_code, account_number, account_name, is_available,
  fcm_token, gov_id_url, selfie_url
) ON public.riders TO authenticated;
