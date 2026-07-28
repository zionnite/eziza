-- External Carriers (Shipbubble) — additive only. A delivery fulfilled by
-- an external carrier is NOT a rider/company bid: it never touches
-- delivery_bids, and must never be picked up by the internal earnings
-- pipeline (credit_delivery_earnings() credits a rider/company wallet on
-- -> confirmed; there is no rider/company here to credit, and the money
-- for this delivery flows OUT to the carrier, not in from a commission).
--
-- Design: reuse deliveries.status='assigned' once booked (same value the
-- internal bid-accept path already uses) so every existing "is this still
-- open for bids" check (rider job boards, riders_see_deliveries RLS,
-- customer_delivery_detail_page.dart's bid section) already treats it as
-- spoken-for with zero changes there. rider_id stays NULL. The new
-- fulfillment_channel column is what actually protects the earnings
-- trigger, same shape as its existing is_sandbox guard.

ALTER TABLE public.deliveries
  ADD COLUMN IF NOT EXISTS fulfillment_channel TEXT NOT NULL DEFAULT 'internal'
    CHECK (fulfillment_channel IN ('internal', 'external_carrier'));

-- ── credit_delivery_earnings(): one more early-return, same shape as the
-- existing is_sandbox guard already in this function.
CREATE OR REPLACE FUNCTION public.credit_delivery_earnings()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  v_fee_pct    NUMERIC;
  v_gross      NUMERIC;
  v_commission NUMERIC;
  v_net        NUMERIC;
  v_company_id UUID;
BEGIN
  IF NEW.status != 'confirmed' OR OLD.status IS NOT DISTINCT FROM 'confirmed' THEN
    RETURN NEW;
  END IF;
  IF NEW.is_sandbox THEN
    RETURN NEW;
  END IF;
  IF NEW.fulfillment_channel = 'external_carrier' THEN
    RETURN NEW;
  END IF;

  SELECT (value::NUMERIC) INTO v_fee_pct FROM public.settings WHERE key = 'platform_fee_pct';
  v_fee_pct := COALESCE(v_fee_pct, 0.10);

  v_gross := COALESCE(NEW.agreed_price, 0);
  v_commission := ROUND(v_gross * v_fee_pct, 2);
  v_net := v_gross - v_commission;

  SELECT company_id INTO v_company_id
  FROM public.delivery_bids WHERE delivery_id = NEW.id AND status = 'accepted';

  UPDATE public.deliveries SET
    platform_fee = v_commission,
    delivery_fee_breakdown = jsonb_build_object(
      'gross_amount', v_gross, 'commission_pct', v_fee_pct,
      'commission_amount', v_commission, 'net_amount', v_net)
  WHERE id = NEW.id;

  INSERT INTO public.earnings_ledger (delivery_id, rider_id, company_id, gross_amount, commission_amount, net_amount)
  VALUES (NEW.id, CASE WHEN v_company_id IS NULL THEN NEW.rider_id END, v_company_id, v_gross, v_commission, v_net);

  IF v_company_id IS NOT NULL THEN
    UPDATE public.companies SET
      wallet_balance = COALESCE(wallet_balance, 0) + v_net,
      total_earned   = COALESCE(total_earned, 0) + v_net
    WHERE id = v_company_id;
  ELSE
    UPDATE public.riders SET wallet_balance = COALESCE(wallet_balance, 0) + v_net WHERE id = NEW.rider_id;
  END IF;

  RETURN NEW;
END;
$function$;

-- ── Tables ──────────────────────────────────────────────────────────────

CREATE TABLE public.external_carrier_quotes (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  delivery_id   UUID NOT NULL REFERENCES public.deliveries(id) ON DELETE CASCADE,
  customer_id   UUID NOT NULL REFERENCES public.customers(id),
  courier_id    TEXT,
  courier_name  TEXT,
  service_code  TEXT,
  request_token TEXT NOT NULL,
  total         NUMERIC(12,2),
  currency      TEXT,
  delivery_eta  TEXT,
  raw_response  JSONB,
  fetched_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at    TIMESTAMPTZ
);
CREATE INDEX idx_external_carrier_quotes_delivery ON public.external_carrier_quotes (delivery_id);

CREATE TABLE public.external_carrier_bookings (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  delivery_id         UUID NOT NULL UNIQUE REFERENCES public.deliveries(id) ON DELETE CASCADE,
  quote_id            UUID REFERENCES public.external_carrier_quotes(id),
  customer_id         UUID NOT NULL REFERENCES public.customers(id),
  shipbubble_order_id TEXT NOT NULL,
  courier_id          TEXT,
  courier_name        TEXT,
  service_code        TEXT,
  tracking_url        TEXT,
  shipping_fee        NUMERIC(12,2) NOT NULL,
  currency            TEXT,
  status              TEXT NOT NULL DEFAULT 'pending'
                       CHECK (status IN ('pending','confirmed','picked_up','in_transit','completed','cancelled')),
  status_history      JSONB NOT NULL DEFAULT '[]'::jsonb,
  booked_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  cancelled_at        TIMESTAMPTZ,
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_external_carrier_bookings_customer ON public.external_carrier_bookings (customer_id);

-- Lock down like every other customer-facing table in this project
-- (riders/companies/deliveries/customers already got this in Phase 4) --
-- new tables inherit Supabase's default blanket grant otherwise, the exact
-- gap that phase closed elsewhere.
REVOKE ALL ON public.external_carrier_quotes FROM anon, authenticated;
GRANT SELECT ON public.external_carrier_quotes TO authenticated;

REVOKE ALL ON public.external_carrier_bookings FROM anon, authenticated;
GRANT SELECT ON public.external_carrier_bookings TO authenticated;

ALTER TABLE public.external_carrier_quotes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.external_carrier_bookings ENABLE ROW LEVEL SECURITY;

CREATE POLICY external_carrier_quotes_select_own ON public.external_carrier_quotes
  FOR SELECT USING (customer_id = auth.uid());

CREATE POLICY external_carrier_bookings_select_own ON public.external_carrier_bookings
  FOR SELECT USING (customer_id = auth.uid());

-- ── Guard: a delivery with an external carrier booking can't also be bid
-- on by a rider/company -- mirrors ZeeFashion's own
-- reject_bids_on_eziza_requests trigger (same problem, same fix shape).
CREATE OR REPLACE FUNCTION public.reject_bids_on_external_carrier_deliveries()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.external_carrier_bookings WHERE delivery_id = NEW.delivery_id
  ) THEN
    RAISE EXCEPTION 'This delivery has an external carrier booking -- internal bids are not allowed';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_reject_bids_on_external_carrier_deliveries ON public.delivery_bids;
CREATE TRIGGER trg_reject_bids_on_external_carrier_deliveries
  BEFORE INSERT ON public.delivery_bids
  FOR EACH ROW EXECUTE FUNCTION public.reject_bids_on_external_carrier_deliveries();

-- ── Payment: verify balance -> Shipbubble create-shipment call happens in
-- the edge function -> only on Shipbubble success does this RPC run,
-- mirroring pay_and_accept_delivery_bid's own shape and the precheck/
-- finalize pattern already proven for ZeeFashion's Eziza-bid-accept flow.
CREATE OR REPLACE FUNCTION public.finalize_book_external_carrier(
  p_quote_id            UUID,
  p_customer_id         UUID,
  p_shipbubble_order_id TEXT,
  p_tracking_url        TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_quote    RECORD;
  v_delivery RECORD;
  v_balance  NUMERIC;
  v_booking_id UUID;
BEGIN
  IF auth.uid() IS DISTINCT FROM p_customer_id THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  SELECT * INTO v_quote FROM public.external_carrier_quotes WHERE id = p_quote_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Quote not found'; END IF;
  IF v_quote.customer_id != p_customer_id THEN RAISE EXCEPTION 'Not authorized for this quote'; END IF;

  SELECT * INTO v_delivery FROM public.deliveries WHERE id = v_quote.delivery_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Delivery not found'; END IF;
  IF v_delivery.customer_id != p_customer_id THEN RAISE EXCEPTION 'Not authorized for this delivery'; END IF;
  IF v_delivery.status != 'open' THEN RAISE EXCEPTION 'Delivery is not open'; END IF;

  IF EXISTS (SELECT 1 FROM public.external_carrier_bookings WHERE delivery_id = v_quote.delivery_id) THEN
    RAISE EXCEPTION 'This delivery already has an external carrier booking';
  END IF;

  SELECT COALESCE(wallet_balance, 0) INTO v_balance FROM public.customers WHERE id = p_customer_id;
  IF v_balance < v_quote.total THEN
    RAISE EXCEPTION 'Insufficient wallet balance';
  END IF;

  INSERT INTO public.wallet_transactions (customer_id, amount, type, description, reference)
  VALUES (p_customer_id, v_quote.total, 'debit', 'External carrier shipping fee', p_shipbubble_order_id);

  INSERT INTO public.external_carrier_bookings (
    delivery_id, quote_id, customer_id, shipbubble_order_id, courier_id, courier_name,
    service_code, tracking_url, shipping_fee, currency, status
  ) VALUES (
    v_quote.delivery_id, p_quote_id, p_customer_id, p_shipbubble_order_id, v_quote.courier_id, v_quote.courier_name,
    v_quote.service_code, p_tracking_url, v_quote.total, v_quote.currency, 'pending'
  ) RETURNING id INTO v_booking_id;

  UPDATE public.deliveries SET
    status              = 'assigned',
    fulfillment_channel = 'external_carrier',
    agreed_price        = v_quote.total,
    payment_source      = 'wallet',
    payment_ref          = p_shipbubble_order_id,
    payment_status      = 'paid',
    assigned_at         = now()
  WHERE id = v_quote.delivery_id;

  RETURN v_booking_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.finalize_book_external_carrier(UUID, UUID, TEXT, TEXT) TO authenticated;

-- ── Cancellation refund — same idempotency shape as ZeeFashion's
-- delivery.cancelled refund fix, just enforced via a row lock (FOR UPDATE)
-- + pre-check instead of a conditional UPDATE...RETURNING, since this is
-- one plpgsql transaction rather than separate JS/TS calls.
CREATE OR REPLACE FUNCTION public.cancel_external_carrier_booking(
  p_booking_id  UUID,
  p_customer_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_booking RECORD;
BEGIN
  IF auth.uid() IS DISTINCT FROM p_customer_id THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  SELECT * INTO v_booking FROM public.external_carrier_bookings WHERE id = p_booking_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Booking not found'; END IF;
  IF v_booking.customer_id != p_customer_id THEN RAISE EXCEPTION 'Not authorized for this booking'; END IF;
  IF v_booking.status IN ('cancelled', 'completed') THEN
    RAISE EXCEPTION 'Cannot cancel a booking with status %', v_booking.status;
  END IF;

  UPDATE public.external_carrier_bookings
  SET status = 'cancelled', cancelled_at = now(), updated_at = now()
  WHERE id = p_booking_id;

  -- Distinct reference from the original debit's -- reference has a unique
  -- index, and reusing shipbubble_order_id verbatim here collided with the
  -- debit row's own reference, found live while testing this function.
  INSERT INTO public.wallet_transactions (customer_id, amount, type, description, reference)
  VALUES (p_customer_id, v_booking.shipping_fee, 'refunded', 'External carrier booking cancelled', 'refund_' || v_booking.shipbubble_order_id);

  UPDATE public.deliveries SET status = 'cancelled', cancelled_at = now()
  WHERE id = v_booking.delivery_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.cancel_external_carrier_booking(UUID, UUID) TO authenticated;
