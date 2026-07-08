-- Phase 3: customer-initiated cancel, refunding the wallet if the delivery
-- was paid. Same cancellable-status scope as the existing cancel-delivery
-- edge function (open | assigned) — once a rider has picked up, this isn't
-- a self-serve cancel anymore.
CREATE OR REPLACE FUNCTION public.cancel_delivery_with_refund(
  p_delivery_id UUID,
  p_customer_id UUID,
  p_reason      TEXT DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status         TEXT;
  v_payment_status TEXT;
  v_agreed_price   NUMERIC;
BEGIN
  IF auth.uid() IS DISTINCT FROM p_customer_id THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  SELECT status, payment_status, agreed_price
  INTO   v_status, v_payment_status, v_agreed_price
  FROM   public.deliveries
  WHERE  id = p_delivery_id AND customer_id = p_customer_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Delivery not found';
  END IF;

  IF v_status NOT IN ('open', 'assigned') THEN
    RAISE EXCEPTION 'Cannot cancel a delivery with status %', v_status;
  END IF;

  IF v_payment_status = 'paid' AND v_agreed_price IS NOT NULL THEN
    INSERT INTO public.wallet_transactions (customer_id, amount, type, description, reference)
    VALUES (p_customer_id, v_agreed_price, 'refunded', 'Delivery cancelled', p_delivery_id::text || ':refund');
  END IF;

  UPDATE public.deliveries SET
    status         = 'cancelled',
    cancelled_at   = now(),
    cancel_reason  = p_reason,
    payment_status = CASE WHEN v_payment_status = 'paid' THEN 'refunded' ELSE v_payment_status END
  WHERE id = p_delivery_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.cancel_delivery_with_refund(UUID, UUID, TEXT) TO authenticated;
