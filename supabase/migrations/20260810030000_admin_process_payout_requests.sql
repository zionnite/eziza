-- eziza-admin had no UI at all for rider/company payout requests -- not
-- even a visibility gap like tenant top-ups, there was simply nothing.
-- Confirmed live 2026-08-10: two real rider requests (₦4,500 and ₦23,703,
-- the latter sitting since 2026-07-07) and one real company request
-- (₦111,447.90, also since 2026-07-07) had been invisible for over a month.
--
-- Both RPCs are the atomic "admin marks it paid" action: debits the
-- requester's wallet_balance and flips the request to 'paid' in one
-- transaction, row-locked so a double-click can't double-debit, and
-- blocked outright if the current balance can't cover the requested
-- amount (found exactly this case live -- a company's balance had drifted
-- below its own month-old request amount since it was made; better to
-- surface that as a hard error than silently push a wallet negative).
-- 'rejected' just closes the request out, no wallet touch.
CREATE OR REPLACE FUNCTION public.admin_process_rider_payout(
  p_request_id UUID,
  p_action     TEXT -- 'paid' | 'rejected'
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rider_id UUID;
  v_amount   NUMERIC;
  v_balance  NUMERIC;
BEGIN
  IF p_action NOT IN ('paid', 'rejected') THEN
    RAISE EXCEPTION 'action must be paid or rejected';
  END IF;

  SELECT rider_id, amount INTO v_rider_id, v_amount
  FROM public.rider_payout_requests
  WHERE id = p_request_id AND status = 'pending'
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Payout request not found or already processed';
  END IF;

  IF p_action = 'paid' THEN
    SELECT wallet_balance INTO v_balance FROM public.riders WHERE id = v_rider_id FOR UPDATE;
    IF COALESCE(v_balance, 0) < v_amount THEN
      RAISE EXCEPTION 'Rider''s current balance (%) is less than the requested payout (%)', v_balance, v_amount;
    END IF;
    UPDATE public.riders SET wallet_balance = wallet_balance - v_amount WHERE id = v_rider_id;
    UPDATE public.rider_payout_requests SET status = 'paid', paid_at = now() WHERE id = p_request_id;
  ELSE
    UPDATE public.rider_payout_requests SET status = 'rejected' WHERE id = p_request_id;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_process_rider_payout(UUID, TEXT) TO service_role;

CREATE OR REPLACE FUNCTION public.admin_process_company_payout(
  p_request_id UUID,
  p_action     TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id UUID;
  v_amount     NUMERIC;
  v_balance    NUMERIC;
BEGIN
  IF p_action NOT IN ('paid', 'rejected') THEN
    RAISE EXCEPTION 'action must be paid or rejected';
  END IF;

  SELECT company_id, amount INTO v_company_id, v_amount
  FROM public.company_payout_requests
  WHERE id = p_request_id AND status = 'pending'
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Payout request not found or already processed';
  END IF;

  IF p_action = 'paid' THEN
    SELECT wallet_balance INTO v_balance FROM public.companies WHERE id = v_company_id FOR UPDATE;
    IF COALESCE(v_balance, 0) < v_amount THEN
      RAISE EXCEPTION 'Company''s current balance (%) is less than the requested payout (%)', v_balance, v_amount;
    END IF;
    UPDATE public.companies
      SET wallet_balance = wallet_balance - v_amount,
          paid_out       = COALESCE(paid_out, 0) + v_amount
      WHERE id = v_company_id;
    UPDATE public.company_payout_requests SET status = 'paid', processed_at = now() WHERE id = p_request_id;
  ELSE
    UPDATE public.company_payout_requests SET status = 'rejected', processed_at = now() WHERE id = p_request_id;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_process_company_payout(UUID, TEXT) TO service_role;
