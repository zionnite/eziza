-- external_carrier_bookings had no ETA or pickup/dropoff info at all --
-- the quote (external_carrier_quotes) carried pickup_eta/delivery_eta/
-- service_type, but none of it survived past booking, so the booking card
-- only ever showed a bare "pending" status with nothing else. Copied over
-- from the quote at booking time in finalize_book_external_carrier below,
-- since the quote row itself isn't guaranteed to still exist/be relevant
-- after booking (mirrors the same "carry it forward at commit time" pattern
-- already used on the ZeeFashion side for delivery_requests.carrier_pickup_eta).
ALTER TABLE public.external_carrier_bookings
  ADD COLUMN IF NOT EXISTS pickup_eta   text,
  ADD COLUMN IF NOT EXISTS delivery_eta text,
  ADD COLUMN IF NOT EXISTS service_type text;

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
    service_code, tracking_url, shipping_fee, currency, status, pickup_eta, delivery_eta, service_type
  ) VALUES (
    v_quote.delivery_id, p_quote_id, p_customer_id, p_shipbubble_order_id, v_quote.courier_id, v_quote.courier_name,
    v_quote.service_code, p_tracking_url, v_quote.total, v_quote.currency, 'pending',
    v_quote.pickup_eta, v_quote.delivery_eta, v_quote.service_type
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
