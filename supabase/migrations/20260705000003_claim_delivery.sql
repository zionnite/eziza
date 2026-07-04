-- Recipients can claim a delivery by package ID, giving them full
-- tracking + confirm-receipt access regardless of phone number match.

ALTER TABLE deliveries ADD COLUMN IF NOT EXISTS recipient_auth_id uuid REFERENCES auth.users(id);

CREATE INDEX IF NOT EXISTS deliveries_recipient_auth_idx ON deliveries (recipient_auth_id);

-- Claimed recipients can read their deliveries.
CREATE POLICY "claimed_recipient_can_read_delivery" ON deliveries
  FOR SELECT
  USING (recipient_auth_id = auth.uid());

-- Claimed recipients can flip status delivered → confirmed only.
CREATE POLICY "claimed_recipient_can_confirm_receipt" ON deliveries
  FOR UPDATE
  USING (recipient_auth_id = auth.uid() AND status = 'delivered')
  WITH CHECK (status = 'confirmed');

-- ── preview_delivery ──────────────────────────────────────────────────────────
-- Returns sanitised delivery info (no contact details) so the recipient can
-- verify it's their package before claiming.  Accepts the 8-char short ID
-- (first 8 hex chars of the UUID as shown in the app) OR the full UUID.
CREATE OR REPLACE FUNCTION preview_delivery(p_id text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_delivery deliveries%ROWTYPE;
  v_uid      uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  IF length(trim(p_id)) = 0 THEN
    RETURN jsonb_build_object('error', 'Delivery ID is required');
  END IF;

  -- Short prefix (≤ 8 chars) → prefix match; anything longer → exact UUID.
  IF length(trim(p_id)) <= 8 THEN
    SELECT * INTO v_delivery
    FROM   deliveries
    WHERE  id::text ILIKE (lower(trim(p_id)) || '%')
    ORDER  BY created_at DESC
    LIMIT  1;
  ELSE
    BEGIN
      SELECT * INTO v_delivery FROM deliveries WHERE id = trim(p_id)::uuid;
    EXCEPTION WHEN OTHERS THEN
      RETURN jsonb_build_object('error', 'Invalid delivery ID format');
    END;
  END IF;

  IF v_delivery.id IS NULL THEN
    RETURN jsonb_build_object('error', 'No delivery found with that ID. Check the ID and try again.');
  END IF;

  IF v_delivery.customer_id = v_uid THEN
    RETURN jsonb_build_object('error', 'This is a delivery you sent — you cannot claim it as a recipient.');
  END IF;

  IF v_delivery.recipient_auth_id IS NOT NULL AND v_delivery.recipient_auth_id != v_uid THEN
    RETURN jsonb_build_object('error', 'This delivery has already been claimed by another account.');
  END IF;

  RETURN jsonb_build_object(
    'ok',               true,
    'delivery_id',      v_delivery.id,
    'status',           v_delivery.status,
    'pickup_address',   v_delivery.pickup_address,
    'delivery_address', v_delivery.delivery_address,
    'agreed_price',     v_delivery.agreed_price,
    'already_claimed',  COALESCE(v_delivery.recipient_auth_id = v_uid, false)
  );
END;
$$;

-- ── claim_delivery ────────────────────────────────────────────────────────────
-- Sets recipient_auth_id = auth.uid() on the delivery. Idempotent.
CREATE OR REPLACE FUNCTION claim_delivery(p_id text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_delivery deliveries%ROWTYPE;
  v_uid      uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  IF length(trim(p_id)) <= 8 THEN
    SELECT * INTO v_delivery
    FROM   deliveries
    WHERE  id::text ILIKE (lower(trim(p_id)) || '%')
    ORDER  BY created_at DESC
    LIMIT  1
    FOR UPDATE;
  ELSE
    BEGIN
      SELECT * INTO v_delivery FROM deliveries WHERE id = trim(p_id)::uuid FOR UPDATE;
    EXCEPTION WHEN OTHERS THEN
      RETURN jsonb_build_object('error', 'Invalid delivery ID format');
    END;
  END IF;

  IF v_delivery.id IS NULL THEN
    RETURN jsonb_build_object('error', 'No delivery found with that ID.');
  END IF;

  IF v_delivery.customer_id = v_uid THEN
    RETURN jsonb_build_object('error', 'This is a delivery you sent.');
  END IF;

  IF v_delivery.recipient_auth_id IS NOT NULL AND v_delivery.recipient_auth_id != v_uid THEN
    RETURN jsonb_build_object('error', 'This delivery has already been claimed by another account.');
  END IF;

  -- Already claimed by this user — idempotent, just return success.
  IF v_delivery.recipient_auth_id = v_uid THEN
    RETURN jsonb_build_object('ok', true, 'delivery_id', v_delivery.id, 'already_claimed', true);
  END IF;

  UPDATE deliveries SET recipient_auth_id = v_uid WHERE id = v_delivery.id;

  RETURN jsonb_build_object('ok', true, 'delivery_id', v_delivery.id, 'already_claimed', false);
END;
$$;
