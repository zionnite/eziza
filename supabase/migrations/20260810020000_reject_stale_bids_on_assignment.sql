-- Bug: company dashboard "Pending Offers" kept showing an offer as pending
-- after the delivery was booked through an External Carrier (Shipbubble) --
-- confirmed live 2026-08-10. pay_and_accept_delivery_bid already rejects
-- sibling pending bids when an internal bid wins (see 20260711030000), but
-- finalize_book_external_carrier / finalize_book_external_carrier_for_tenant
-- never touch delivery_bids at all, so a bid placed before the customer
-- booked an external carrier was left stuck at status='pending' forever.
--
-- Rather than patch every place a delivery can leave 'open' (there are
-- already at least 3: internal bid accept, external carrier booking x2 for
-- direct + tenant deliveries, plus cancellation), a single trigger on
-- deliveries covers all of them going forward.
CREATE OR REPLACE FUNCTION public.reject_pending_bids_on_delivery_left_open()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.delivery_bids
    SET status = 'rejected'
    WHERE delivery_id = NEW.id AND status = 'pending';
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_reject_pending_bids_on_delivery_left_open ON public.deliveries;
CREATE TRIGGER trg_reject_pending_bids_on_delivery_left_open
  AFTER UPDATE ON public.deliveries
  FOR EACH ROW
  WHEN (OLD.status = 'open' AND NEW.status IS DISTINCT FROM 'open')
  EXECUTE FUNCTION public.reject_pending_bids_on_delivery_left_open();

-- One-off backfill for bids already stuck stale from before this trigger
-- existed (e.g. the external-carrier booking made live during today's
-- testing).
UPDATE public.delivery_bids b
  SET status = 'rejected'
  WHERE b.status = 'pending'
    AND EXISTS (
      SELECT 1 FROM public.deliveries d
      WHERE d.id = b.delivery_id AND d.status != 'open'
    );
