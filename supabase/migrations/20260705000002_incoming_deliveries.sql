-- Recipients can view and confirm deliveries addressed to their phone number.
-- Phone numbers are normalised (08x → 234x) so format differences don't break matching.

CREATE OR REPLACE FUNCTION normalize_phone(raw text) RETURNS text
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  digits text;
BEGIN
  IF raw IS NULL OR trim(raw) = '' THEN RETURN NULL; END IF;
  digits := regexp_replace(raw, '[^0-9]', '', 'g');
  IF digits = '' THEN RETURN NULL; END IF;
  IF left(digits, 1) = '0'   THEN RETURN '234' || substring(digits FROM 2); END IF;
  IF left(digits, 3) = '234' THEN RETURN digits; END IF;
  RETURN digits;
END;
$$;

-- Allow users to read deliveries where they are the named recipient.
CREATE POLICY "recipient_can_read_delivery" ON deliveries
  FOR SELECT
  USING (
    normalize_phone(delivery_contact_phone) IS NOT NULL
    AND normalize_phone(delivery_contact_phone)
        = normalize_phone((auth.jwt() -> 'user_metadata' ->> 'phone'))
  );

-- Allow recipients to flip status from delivered → confirmed only.
CREATE POLICY "recipient_can_confirm_receipt" ON deliveries
  FOR UPDATE
  USING (
    normalize_phone(delivery_contact_phone) IS NOT NULL
    AND normalize_phone(delivery_contact_phone)
        = normalize_phone((auth.jwt() -> 'user_metadata' ->> 'phone'))
    AND status = 'delivered'
  )
  WITH CHECK (status = 'confirmed');
