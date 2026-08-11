-- Closes the "uncollected-commission gap" documented in
-- 20260730000000_external_carriers_for_tenants.sql: a tenant-routed
-- delivery fulfilled by an Eziza rider/company previously had NO payment
-- step at all -- accept-bid just flipped status, and credit_delivery_
-- earnings() still credited the rider/company in full once confirmed,
-- with nothing ever collected from the tenant. Confirmed live 2026-08-10
-- via a full money-flow trace requested by the user.
--
-- Same prepaid-wallet mechanism External Carrier bookings already use
-- (finalize_book_external_carrier_for_tenant) -- debits the tenant's
-- existing wallet_balance the full bid amount atomically with accepting
-- it, row-locked (delivery + bid + tenant) so a retried/duplicate call
-- can't double-debit, hard-blocked if the balance can't cover it.
CREATE OR REPLACE FUNCTION public.accept_bid_for_tenant(
  p_delivery_id UUID,
  p_bid_id      UUID,
  p_tenant_id   UUID
)
RETURNS TABLE (rider_id UUID, agreed_price NUMERIC)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_delivery RECORD;
  v_bid      RECORD;
  v_balance  NUMERIC;
BEGIN
  SELECT * INTO v_delivery FROM public.deliveries
  WHERE id = p_delivery_id AND tenant_id = p_tenant_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Delivery not found';
  END IF;
  IF v_delivery.status != 'open' THEN
    RAISE EXCEPTION 'Cannot accept a bid on a delivery with status ''%''', v_delivery.status;
  END IF;

  SELECT * INTO v_bid FROM public.delivery_bids
  WHERE id = p_bid_id AND delivery_id = p_delivery_id AND status = 'pending'
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Bid not found or already processed';
  END IF;

  SELECT wallet_balance INTO v_balance FROM public.tenants WHERE id = p_tenant_id FOR UPDATE;
  IF COALESCE(v_balance, 0) < v_bid.amount THEN
    RAISE EXCEPTION 'Insufficient tenant balance';
  END IF;

  -- reference = delivery id: only one bid can ever win a given delivery
  -- (siblings get rejected below), so this doubles as an idempotency guard
  -- via tenant_wallet_transactions' unique index on reference, on top of
  -- the FOR UPDATE lock above already serializing concurrent attempts.
  INSERT INTO public.tenant_wallet_transactions (tenant_id, amount, type, description, reference)
  VALUES (p_tenant_id, v_bid.amount, 'debit', 'Delivery fee (internal rider/company)', p_delivery_id::text);

  UPDATE public.delivery_bids SET status = 'accepted' WHERE id = p_bid_id;
  UPDATE public.delivery_bids SET status = 'rejected'
    WHERE delivery_id = p_delivery_id AND id != p_bid_id AND status = 'pending';

  UPDATE public.deliveries SET
    status       = 'assigned',
    rider_id     = v_bid.rider_id,
    agreed_price = v_bid.amount,
    assigned_at  = now()
  WHERE id = p_delivery_id;

  RETURN QUERY SELECT v_bid.rider_id, v_bid.amount;
END;
$$;

GRANT EXECUTE ON FUNCTION public.accept_bid_for_tenant(UUID, UUID, UUID) TO service_role;
