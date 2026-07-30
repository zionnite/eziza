-- Follow-up fix: the previous migration's backfill only inserted a code for
-- deliveries with NO existing delivery_otps row. Deliveries that already had
-- a row from the old SMS-request flow (created when a rider tapped "send")
-- were skipped and left with code = NULL after otp_hash was dropped.

UPDATE delivery_otps
SET code = generate_handoff_code()
WHERE code IS NULL AND verified_at IS NULL;
