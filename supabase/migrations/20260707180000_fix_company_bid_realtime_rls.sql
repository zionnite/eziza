-- Same root cause as 20260707100000_fix_deliveries_realtime_rls.sql, this
-- time for companies: deliveries_rider_select's company-visibility clause
-- ("id IN (SELECT _auth_company_bid_delivery_ids())") is a subquery/function
-- call, which Supabase Realtime's postgres_changes authorization does not
-- reliably evaluate. A company that bids on a delivery and then loses it (or
-- wins it) may never receive the UPDATE event once status leaves 'open' —
-- the only other qualifying clauses require being the assigned rider or the
-- customer — so the delivery sits in that company's open-for-bid list
-- forever even though it's no longer open.
--
-- Fix: denormalize into a UUID[] column keyed on the bidding companies'
-- auth_user_id (not company_id), so the RLS check becomes a direct
-- `auth.uid() = ANY(...)` array containment test — no subquery, no join.

ALTER TABLE public.deliveries
  ADD COLUMN IF NOT EXISTS bidder_company_auth_ids UUID[] NOT NULL DEFAULT '{}';

CREATE OR REPLACE FUNCTION public.sync_deliveries_bidder_company_auth_ids()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  v_auth_id UUID;
BEGIN
  IF NEW.company_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT auth_user_id INTO v_auth_id
  FROM public.companies WHERE id = NEW.company_id;

  IF v_auth_id IS NOT NULL THEN
    UPDATE public.deliveries
    SET bidder_company_auth_ids = ARRAY(
      SELECT DISTINCT unnest(bidder_company_auth_ids || v_auth_id)
    )
    WHERE id = NEW.delivery_id
      AND NOT (bidder_company_auth_ids @> ARRAY[v_auth_id]);
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_deliveries_bidder_company_auth_ids ON public.delivery_bids;
CREATE TRIGGER trg_sync_deliveries_bidder_company_auth_ids
  AFTER INSERT ON public.delivery_bids
  FOR EACH ROW EXECUTE FUNCTION public.sync_deliveries_bidder_company_auth_ids();

-- Backfill existing rows from bid history.
UPDATE public.deliveries d
SET bidder_company_auth_ids = ARRAY(
  SELECT DISTINCT c.auth_user_id
  FROM public.delivery_bids db
  JOIN public.companies c ON c.id = db.company_id
  WHERE db.delivery_id = d.id AND db.company_id IS NOT NULL
)
WHERE EXISTS (
  SELECT 1 FROM public.delivery_bids db
  WHERE db.delivery_id = d.id AND db.company_id IS NOT NULL
);

-- Simplify the RLS policy to use the direct array-containment check.
DROP POLICY IF EXISTS deliveries_rider_select ON public.deliveries;
CREATE POLICY deliveries_rider_select ON public.deliveries FOR SELECT
USING (
  status = 'open'
  OR customer_id = auth.uid()
  OR rider_auth_user_id = auth.uid()
  OR auth.uid() = ANY(bidder_company_auth_ids)
);
