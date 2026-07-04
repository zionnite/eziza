-- Fix infinite RLS recursion on deliveries ↔ delivery_bids.
--
-- Root cause:
--   deliveries SELECT policy  → subquery on delivery_bids
--   delivery_bids SELECT policy → subquery on deliveries
--   Each triggers the other → 42P17 infinite recursion.
--
-- Fix: SECURITY DEFINER helper functions bypass RLS on the tables they query,
-- breaking both recursion chains.

-- ── Helper functions ────────────────────────────────────────────────────────

-- Delivery IDs owned by the current user (used in delivery_bids policies)
CREATE OR REPLACE FUNCTION _auth_customer_delivery_ids()
RETURNS SETOF uuid
LANGUAGE sql SECURITY DEFINER SET search_path = public
AS $$
  SELECT id FROM deliveries WHERE customer_id = auth.uid();
$$;

-- Delivery IDs where the current user's company has a bid (used in deliveries policy)
CREATE OR REPLACE FUNCTION _auth_company_bid_delivery_ids()
RETURNS SETOF uuid
LANGUAGE sql SECURITY DEFINER SET search_path = public
AS $$
  SELECT db.delivery_id
  FROM delivery_bids db
  JOIN companies c ON c.id = db.company_id
  WHERE c.auth_user_id = auth.uid();
$$;

-- ── Recreate deliveries SELECT policy ──────────────────────────────────────

DROP POLICY IF EXISTS deliveries_rider_select ON deliveries;
CREATE POLICY deliveries_rider_select ON deliveries FOR SELECT
USING (
  status = 'open'
  OR customer_id = auth.uid()
  OR rider_id IN (SELECT id FROM riders WHERE auth_user_id = auth.uid())
  OR id IN (SELECT _auth_company_bid_delivery_ids())
);

-- ── Recreate delivery_bids policies ────────────────────────────────────────

DROP POLICY IF EXISTS bids_customer_select ON delivery_bids;
CREATE POLICY bids_customer_select ON delivery_bids FOR SELECT
USING (
  delivery_id IN (SELECT _auth_customer_delivery_ids())
);

DROP POLICY IF EXISTS bids_customer_update ON delivery_bids;
CREATE POLICY bids_customer_update ON delivery_bids FOR UPDATE
USING (
  delivery_id IN (SELECT _auth_customer_delivery_ids())
);
