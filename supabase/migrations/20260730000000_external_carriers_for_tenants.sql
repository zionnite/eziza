-- External Carriers, extended to tenants (ZeeFashion + any eziza-partners
-- tenant). A tenant-routed delivery has no Eziza customer/wallet attached
-- at all, so the customer-facing flow (20260729000000) doesn't reach it.
-- Tenant prepays a balance with Eziza first -- confirmed decision, real
-- money exposure otherwise (Eziza fronting a real third-party cost with no
-- collection mechanism, materially different from the already-accepted
-- uncollected-commission gap).

-- ── Tenant wallet ──────────────────────────────────────────────────────
ALTER TABLE public.tenants
  ADD COLUMN IF NOT EXISTS wallet_balance NUMERIC NOT NULL DEFAULT 0;

CREATE TABLE public.tenant_wallet_transactions (
  id          BIGSERIAL PRIMARY KEY,
  tenant_id   UUID NOT NULL REFERENCES public.tenants(id),
  amount      NUMERIC NOT NULL,
  type        TEXT NOT NULL CHECK (type IN ('credit', 'debit', 'refunded')),
  description TEXT,
  reference   TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_tenant_wallet_transactions_tenant ON public.tenant_wallet_transactions (tenant_id);
CREATE UNIQUE INDEX idx_tenant_wallet_transactions_reference
  ON public.tenant_wallet_transactions (reference) WHERE reference IS NOT NULL;

-- Same incremental-crediting shape as credit_wallet_transaction() (customers)
-- -- never UPDATE tenants.wallet_balance directly alongside an insert here.
CREATE OR REPLACE FUNCTION public.credit_tenant_wallet_transaction()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.type IN ('credit', 'refunded') THEN
    UPDATE public.tenants SET wallet_balance = COALESCE(wallet_balance, 0) + NEW.amount WHERE id = NEW.tenant_id;
  ELSIF NEW.type = 'debit' THEN
    UPDATE public.tenants SET wallet_balance = COALESCE(wallet_balance, 0) - NEW.amount WHERE id = NEW.tenant_id;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_credit_tenant_wallet_transaction
  AFTER INSERT ON public.tenant_wallet_transactions
  FOR EACH ROW EXECUTE FUNCTION public.credit_tenant_wallet_transaction();

-- Locked down like every other financial table in this project. Writes
-- only ever happen via SECURITY DEFINER RPCs or eziza-admin's own
-- service-role route (manual balance adjustment) -- no direct
-- authenticated write path needed at all.
REVOKE ALL ON public.tenant_wallet_transactions FROM anon, authenticated;
GRANT SELECT ON public.tenant_wallet_transactions TO authenticated;
ALTER TABLE public.tenant_wallet_transactions ENABLE ROW LEVEL SECURITY;

-- A tenant's own eziza-partners login (tenants.auth_user_id) can read its
-- own transaction history -- a plain historical SELECT, not a Realtime
-- subscription, so the subquery-reliability issue that forced denormalizing
-- other RLS policies in this project doesn't apply here.
CREATE POLICY tenant_wallet_transactions_select_own ON public.tenant_wallet_transactions
  FOR SELECT USING (
    tenant_id IN (SELECT id FROM public.tenants WHERE auth_user_id = auth.uid())
  );

-- ── Package details on deliveries, populated optionally at creation ────
ALTER TABLE public.deliveries
  ADD COLUMN IF NOT EXISTS package_category_id INT,
  ADD COLUMN IF NOT EXISTS package_weight_kg   NUMERIC,
  ADD COLUMN IF NOT EXISTS package_dimension   JSONB; -- {length, width, height} cm

-- ── external_carrier_quotes / external_carrier_bookings: allow a tenant
-- owner instead of a customer owner. Exactly one of the two is set.
ALTER TABLE public.external_carrier_quotes
  ALTER COLUMN customer_id DROP NOT NULL,
  ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id),
  ADD CONSTRAINT external_carrier_quotes_owner_check
    CHECK (
      (customer_id IS NOT NULL AND tenant_id IS NULL) OR
      (customer_id IS NULL AND tenant_id IS NOT NULL)
    );

ALTER TABLE public.external_carrier_bookings
  ALTER COLUMN customer_id DROP NOT NULL,
  ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id),
  ADD CONSTRAINT external_carrier_bookings_owner_check
    CHECK (
      (customer_id IS NOT NULL AND tenant_id IS NULL) OR
      (customer_id IS NULL AND tenant_id IS NOT NULL)
    );

-- ── Tenant-scoped finalize/cancel RPCs ──────────────────────────────────
-- Deliberately NO auth.uid() check and NO grant to `authenticated` --
-- tenant requests never carry a Supabase Auth JWT at all (they're
-- authenticated via validateApiKey() inside the edge function, which uses
-- the service-role client). Granting these to `authenticated` would let
-- ANY logged-in Eziza user call them with an arbitrary tenant_id and drain
-- that tenant's wallet -- the trust boundary is the calling edge
-- function's already-completed validateApiKey() check, not this RPC.
CREATE OR REPLACE FUNCTION public.finalize_book_external_carrier_for_tenant(
  p_quote_id            UUID,
  p_tenant_id            UUID,
  p_shipbubble_order_id TEXT,
  p_tracking_url        TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_quote      RECORD;
  v_delivery   RECORD;
  v_balance    NUMERIC;
  v_booking_id UUID;
BEGIN
  SELECT * INTO v_quote FROM public.external_carrier_quotes WHERE id = p_quote_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Quote not found'; END IF;
  IF v_quote.tenant_id != p_tenant_id THEN RAISE EXCEPTION 'Not authorized for this quote'; END IF;

  SELECT * INTO v_delivery FROM public.deliveries WHERE id = v_quote.delivery_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Delivery not found'; END IF;
  IF v_delivery.tenant_id != p_tenant_id THEN RAISE EXCEPTION 'Not authorized for this delivery'; END IF;
  IF v_delivery.status != 'open' THEN RAISE EXCEPTION 'Delivery is not open'; END IF;

  IF EXISTS (SELECT 1 FROM public.external_carrier_bookings WHERE delivery_id = v_quote.delivery_id) THEN
    RAISE EXCEPTION 'This delivery already has an external carrier booking';
  END IF;

  SELECT COALESCE(wallet_balance, 0) INTO v_balance FROM public.tenants WHERE id = p_tenant_id;
  IF v_balance < v_quote.total THEN
    RAISE EXCEPTION 'Insufficient tenant balance';
  END IF;

  INSERT INTO public.tenant_wallet_transactions (tenant_id, amount, type, description, reference)
  VALUES (p_tenant_id, v_quote.total, 'debit', 'External carrier shipping fee', p_shipbubble_order_id);

  INSERT INTO public.external_carrier_bookings (
    delivery_id, quote_id, tenant_id, shipbubble_order_id, courier_id, courier_name,
    service_code, tracking_url, shipping_fee, currency, status
  ) VALUES (
    v_quote.delivery_id, p_quote_id, p_tenant_id, p_shipbubble_order_id, v_quote.courier_id, v_quote.courier_name,
    v_quote.service_code, p_tracking_url, v_quote.total, v_quote.currency, 'pending'
  ) RETURNING id INTO v_booking_id;

  UPDATE public.deliveries SET
    status              = 'assigned',
    fulfillment_channel = 'external_carrier',
    agreed_price        = v_quote.total
  WHERE id = v_quote.delivery_id;

  RETURN v_booking_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.cancel_external_carrier_booking_for_tenant(
  p_booking_id UUID,
  p_tenant_id  UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_booking RECORD;
BEGIN
  SELECT * INTO v_booking FROM public.external_carrier_bookings WHERE id = p_booking_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Booking not found'; END IF;
  IF v_booking.tenant_id != p_tenant_id THEN RAISE EXCEPTION 'Not authorized for this booking'; END IF;
  IF v_booking.status IN ('cancelled', 'completed') THEN
    RAISE EXCEPTION 'Cannot cancel a booking with status %', v_booking.status;
  END IF;

  UPDATE public.external_carrier_bookings
  SET status = 'cancelled', cancelled_at = now(), updated_at = now()
  WHERE id = p_booking_id;

  INSERT INTO public.tenant_wallet_transactions (tenant_id, amount, type, description, reference)
  VALUES (p_tenant_id, v_booking.shipping_fee, 'refunded', 'External carrier booking cancelled', 'refund_' || v_booking.shipbubble_order_id);

  UPDATE public.deliveries SET status = 'cancelled', cancelled_at = now()
  WHERE id = v_booking.delivery_id;
END;
$$;

-- Explicit revoke rather than relying on assumed defaults -- Postgres
-- grants EXECUTE to PUBLIC on new functions unless revoked, which would
-- otherwise silently undo the "no grant to authenticated" intent above.
REVOKE EXECUTE ON FUNCTION public.finalize_book_external_carrier_for_tenant(UUID, UUID, TEXT, TEXT) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.cancel_external_carrier_booking_for_tenant(UUID, UUID) FROM PUBLIC, anon, authenticated;
