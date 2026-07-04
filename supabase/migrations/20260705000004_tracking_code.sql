-- Replace UUID-prefix preview/claim with proper unique tracking codes.
-- Each delivery gets a 6-char code (A-Z + 2-9, no ambiguous chars O/0/I/1/L).

DROP FUNCTION IF EXISTS preview_delivery(text);
DROP FUNCTION IF EXISTS claim_delivery(text);

ALTER TABLE deliveries ADD COLUMN IF NOT EXISTS tracking_code text;

CREATE UNIQUE INDEX IF NOT EXISTS deliveries_tracking_code_idx ON deliveries (tracking_code);

-- ── Code generation ───────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION generate_tracking_code() RETURNS text
LANGUAGE plpgsql AS $$
DECLARE
  chars text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  code  text;
  i     int;
BEGIN
  LOOP
    code := '';
    FOR i IN 1..6 LOOP
      code := code || substr(chars, floor(random() * length(chars) + 1)::int, 1);
    END LOOP;
    EXIT WHEN NOT EXISTS (SELECT 1 FROM deliveries WHERE tracking_code = code);
  END LOOP;
  RETURN code;
END;
$$;

-- Auto-set on insert.
CREATE OR REPLACE FUNCTION set_tracking_code() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.tracking_code IS NULL OR NEW.tracking_code = '' THEN
    NEW.tracking_code := generate_tracking_code();
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS deliveries_set_tracking_code ON deliveries;
CREATE TRIGGER deliveries_set_tracking_code
  BEFORE INSERT ON deliveries
  FOR EACH ROW EXECUTE FUNCTION set_tracking_code();

-- Backfill existing deliveries.
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN SELECT id FROM deliveries WHERE tracking_code IS NULL LOOP
    UPDATE deliveries SET tracking_code = generate_tracking_code() WHERE id = r.id;
  END LOOP;
END;
$$;

ALTER TABLE deliveries ALTER COLUMN tracking_code SET NOT NULL;

-- ── find_and_claim_delivery ───────────────────────────────────────────────────
-- Looks up by tracking code, claims atomically, returns sanitised delivery info.
-- Idempotent: already-claimed-by-same-user returns delivery without error.
CREATE OR REPLACE FUNCTION find_and_claim_delivery(p_code text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_delivery deliveries%ROWTYPE;
  v_uid      uuid := auth.uid();
  v_code     text := upper(trim(p_code));
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  IF length(v_code) = 0 THEN
    RETURN jsonb_build_object('error', 'Tracking code is required');
  END IF;

  SELECT * INTO v_delivery FROM deliveries WHERE tracking_code = v_code FOR UPDATE;

  IF v_delivery.id IS NULL THEN
    RETURN jsonb_build_object(
      'error', 'No delivery found with that code. Double-check it with the sender.'
    );
  END IF;

  IF v_delivery.customer_id = v_uid THEN
    RETURN jsonb_build_object(
      'error', 'This is a delivery you sent — you cannot track it as a recipient.'
    );
  END IF;

  IF v_delivery.recipient_auth_id IS NOT NULL AND v_delivery.recipient_auth_id != v_uid THEN
    RETURN jsonb_build_object(
      'error', 'This delivery is already linked to another account.'
    );
  END IF;

  -- Claim if not yet claimed by this user.
  IF v_delivery.recipient_auth_id IS NULL THEN
    UPDATE deliveries SET recipient_auth_id = v_uid WHERE id = v_delivery.id;
  END IF;

  RETURN jsonb_build_object(
    'ok',               true,
    'delivery_id',      v_delivery.id,
    'tracking_code',    v_delivery.tracking_code,
    'status',           v_delivery.status,
    'pickup_address',   v_delivery.pickup_address,
    'delivery_address', v_delivery.delivery_address,
    'agreed_price',     v_delivery.agreed_price
  );
END;
$$;
