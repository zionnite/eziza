-- cancel_delivery_with_refund() had zero awareness of external-carrier
-- deliveries -- found live while wiring the tenant extension's picked_up
-- mapping and re-checking the customer-facing cancel button. Without this
-- guard, the generic "Cancel Delivery" button would refund the Eziza
-- wallet and mark the delivery cancelled while the real Shipbubble
-- shipment stayed active, uncancelled, on their side.
CREATE OR REPLACE FUNCTION public.cancel_delivery_with_refund(p_delivery_id uuid, p_customer_id uuid, p_reason text DEFAULT NULL::text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_status              TEXT;
  v_payment_status      TEXT;
  v_agreed_price        NUMERIC;
  v_fulfillment_channel TEXT;
BEGIN
  IF auth.uid() IS DISTINCT FROM p_customer_id THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  SELECT status, payment_status, agreed_price, fulfillment_channel
  INTO   v_status, v_payment_status, v_agreed_price, v_fulfillment_channel
  FROM   public.deliveries
  WHERE  id = p_delivery_id AND customer_id = p_customer_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Delivery not found';
  END IF;

  IF v_fulfillment_channel = 'external_carrier' THEN
    RAISE EXCEPTION 'This delivery is fulfilled by an external carrier -- cancel it from the carrier booking card instead';
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
$function$;
