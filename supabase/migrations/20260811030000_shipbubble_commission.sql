-- External Carrier (Shipbubble) bookings were pure pass-through in both
-- directions — Eziza Direct customers and tenants alike paid exactly the
-- carrier's raw quote, no markup, no commission. Confirmed as a real
-- (lower-urgency than the uncollected-commission gap, but real) monetisation
-- gap during the 2026-08-10/11 money-flow audit. Now takes the same
-- platform_fee_pct commission already used for internal-rider deliveries
-- (credit_delivery_earnings()) — one unified "Eziza platform commission"
-- concept across both fulfillment channels, rather than a second rate to
-- separately configure and reason about.
--
-- Keeps both figures on the row (not just the marked-up total) so Eziza's
-- own actual Shipbubble cost obligation stays distinguishable from what was
-- collected — same reasoning earnings_ledger already applies to internal-
-- rider commission (gross/commission/net), just as two columns here instead
-- of a separate ledger table, since there's no rider/company row for a
-- Shipbubble booking to hang a ledger entry off (earnings_ledger requires
-- exactly one of rider_id/company_id).
ALTER TABLE public.external_carrier_quotes
  ADD COLUMN IF NOT EXISTS carrier_cost      NUMERIC(12,2),
  ADD COLUMN IF NOT EXISTS commission_amount NUMERIC(12,2);

ALTER TABLE public.external_carrier_bookings
  ADD COLUMN IF NOT EXISTS carrier_cost      NUMERIC(12,2),
  ADD COLUMN IF NOT EXISTS commission_amount NUMERIC(12,2);

-- Carry the cost/commission split forward from quote to booking at commit
-- time, same "carry it forward" pattern already used for pickup_eta/
-- delivery_eta/service_type (20260810010000_booking_eta_and_service_type.sql)
-- — the quote row itself isn't guaranteed to still exist/be relevant after
-- booking.
CREATE OR REPLACE FUNCTION public.finalize_book_external_carrier(p_quote_id uuid, p_customer_id uuid, p_shipbubble_order_id text, p_tracking_url text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    service_code, tracking_url, shipping_fee, currency, status, pickup_eta, delivery_eta, service_type,
    carrier_cost, commission_amount
  ) VALUES (
    v_quote.delivery_id, p_quote_id, p_customer_id, p_shipbubble_order_id, v_quote.courier_id, v_quote.courier_name,
    v_quote.service_code, p_tracking_url, v_quote.total, v_quote.currency, 'pending',
    v_quote.pickup_eta, v_quote.delivery_eta, v_quote.service_type,
    v_quote.carrier_cost, v_quote.commission_amount
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
$function$;

CREATE OR REPLACE FUNCTION public.finalize_book_external_carrier_for_tenant(p_quote_id uuid, p_tenant_id uuid, p_shipbubble_order_id text, p_tracking_url text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    service_code, tracking_url, shipping_fee, currency, status,
    carrier_cost, commission_amount
  ) VALUES (
    v_quote.delivery_id, p_quote_id, p_tenant_id, p_shipbubble_order_id, v_quote.courier_id, v_quote.courier_name,
    v_quote.service_code, p_tracking_url, v_quote.total, v_quote.currency, 'pending',
    v_quote.carrier_cost, v_quote.commission_amount
  ) RETURNING id INTO v_booking_id;

  UPDATE public.deliveries SET
    status              = 'assigned',
    fulfillment_channel = 'external_carrier',
    agreed_price        = v_quote.total
  WHERE id = v_quote.delivery_id;

  RETURN v_booking_id;
END;
$function$;
