-- Replace the SMS-delivered, rider-requested OTP with a code that:
--   1. is generated the moment a delivery is created (not when the rider
--      marks it delivered) -- so a busy sender doesn't need to be watching
--      the app right at hand-off time to pass it along
--   2. is readable in plain text by the sender and by a matched/claimed
--      recipient (never by the rider -- delivery_otps stays a separate
--      table specifically so the rider's own `select()` of the deliveries
--      row can never expose it)
--   3. never touches SMS at all -- no provider, no licensing dependency

ALTER TABLE delivery_otps ADD COLUMN IF NOT EXISTS code text;
ALTER TABLE delivery_otps ADD COLUMN IF NOT EXISTS locked_until timestamptz;
ALTER TABLE delivery_otps DROP COLUMN IF EXISTS otp_hash;
ALTER TABLE delivery_otps DROP COLUMN IF EXISTS expires_at;

-- ── Generation ────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION generate_handoff_code() RETURNS text
LANGUAGE plpgsql AS $$
BEGIN
  RETURN lpad((100000 + floor(random() * 900000))::int::text, 6, '0');
END;
$$;

CREATE OR REPLACE FUNCTION set_delivery_handoff_code() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO delivery_otps (delivery_id, code) VALUES (NEW.id, generate_handoff_code());
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS deliveries_set_handoff_code ON deliveries;
CREATE TRIGGER deliveries_set_handoff_code
  AFTER INSERT ON deliveries
  FOR EACH ROW EXECUTE FUNCTION set_delivery_handoff_code();

-- Backfill any delivery still in flight (not yet confirmed/cancelled) that
-- doesn't already have a code row from the old SMS-request flow.
INSERT INTO delivery_otps (delivery_id, code)
SELECT d.id, generate_handoff_code()
FROM deliveries d
WHERE d.status NOT IN ('confirmed', 'cancelled')
  AND NOT EXISTS (SELECT 1 FROM delivery_otps o WHERE o.delivery_id = d.id);

-- ── Visibility: sender + matched/claimed recipient only, never the rider ─────
-- Mirrors the exact same "who counts as the recipient" logic already used by
-- deliveries' own recipient_can_read_delivery / claimed_recipient_can_read_delivery
-- policies, so this stays consistent if that logic ever changes.

DROP POLICY IF EXISTS "sender_can_read_handoff_code" ON delivery_otps;
CREATE POLICY "sender_can_read_handoff_code" ON delivery_otps
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM deliveries d
      WHERE d.id = delivery_id AND d.customer_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "recipient_can_read_handoff_code" ON delivery_otps;
CREATE POLICY "recipient_can_read_handoff_code" ON delivery_otps
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM deliveries d
      WHERE d.id = delivery_id
        AND (
          d.recipient_auth_id = auth.uid()
          OR (
            normalize_phone(d.delivery_contact_phone) IS NOT NULL
            AND normalize_phone(d.delivery_contact_phone)
                = normalize_phone((auth.jwt() -> 'user_metadata' ->> 'phone'))
          )
        )
    )
  );
