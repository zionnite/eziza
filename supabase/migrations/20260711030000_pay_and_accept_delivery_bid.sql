-- Phase 3: atomic wallet-pay + bid-accept, mirroring ZeeFashion's
-- pay_and_accept_delivery_bid. Replaces the previous unconditional accept
-- (customer_delivery_detail_page.dart::_acceptBid) which moved no money at
-- all — riders/companies were being credited via credit_delivery_earnings()
-- with nothing ever collected from the customer.
CREATE OR REPLACE FUNCTION public.pay_and_accept_delivery_bid(
  p_bid_id      UUID,
  p_customer_id UUID
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_delivery_id  UUID;
  v_amount       NUMERIC;
  v_rider_id     UUID;
  v_company_id   UUID;
  v_balance      NUMERIC;
BEGIN
  IF auth.uid() IS DISTINCT FROM p_customer_id THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  SELECT delivery_id, amount, rider_id, company_id
  INTO   v_delivery_id, v_amount, v_rider_id, v_company_id
  FROM   public.delivery_bids
  WHERE  id = p_bid_id AND status = 'pending';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Bid not found or already processed';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.deliveries
    WHERE id = v_delivery_id AND customer_id = p_customer_id AND status = 'open'
  ) THEN
    RAISE EXCEPTION 'Not authorized or delivery is not open';
  END IF;

  SELECT COALESCE(wallet_balance, 0) INTO v_balance
  FROM public.customers WHERE id = p_customer_id;

  IF v_balance < v_amount THEN
    RAISE EXCEPTION 'Insufficient wallet balance';
  END IF;

  INSERT INTO public.wallet_transactions (customer_id, amount, type, description, reference)
  VALUES (p_customer_id, v_amount, 'debit', 'Delivery fee payment', v_delivery_id::text);

  UPDATE public.delivery_bids SET status = 'accepted' WHERE id = p_bid_id;
  UPDATE public.delivery_bids
    SET status = 'rejected'
    WHERE delivery_id = v_delivery_id AND id != p_bid_id AND status = 'pending';

  -- A company-employed rider assigned internally does not get rider_id set
  -- here — only the company itself wins the bid; see customer_delivery_
  -- detail_page.dart's isCompanyBid comment for the race condition this
  -- avoids if a company assigns its own rider before this write lands.
  UPDATE public.deliveries SET
    agreed_price   = v_amount,
    status         = 'assigned',
    rider_id       = CASE WHEN v_company_id IS NULL THEN v_rider_id ELSE rider_id END,
    assigned_at    = now(),
    payment_source = 'wallet',
    payment_status = 'paid'
  WHERE id = v_delivery_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.pay_and_accept_delivery_bid(UUID, UUID) TO authenticated;
