-- Add customer_id to delivery_bids so RLS can use a simple equality check.
-- SECURITY DEFINER function subqueries are unreliable with Supabase Realtime.

ALTER TABLE delivery_bids ADD COLUMN IF NOT EXISTS customer_id UUID REFERENCES auth.users(id);

-- Backfill existing rows
UPDATE delivery_bids db
SET customer_id = d.customer_id
FROM deliveries d
WHERE db.delivery_id = d.id
  AND db.customer_id IS NULL;

-- Auto-populate customer_id on every new bid
CREATE OR REPLACE FUNCTION _set_bid_customer_id()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  SELECT customer_id INTO NEW.customer_id FROM deliveries WHERE id = NEW.delivery_id;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_bid_insert_set_customer ON delivery_bids;
CREATE TRIGGER on_bid_insert_set_customer
BEFORE INSERT ON delivery_bids
FOR EACH ROW EXECUTE FUNCTION _set_bid_customer_id();

-- Recreate customer policies using simple equality (works with Realtime RLS)
DROP POLICY IF EXISTS bids_customer_select ON delivery_bids;
CREATE POLICY bids_customer_select ON delivery_bids FOR SELECT
USING (customer_id = auth.uid());

DROP POLICY IF EXISTS bids_customer_update ON delivery_bids;
CREATE POLICY bids_customer_update ON delivery_bids FOR UPDATE
USING (customer_id = auth.uid());

-- Drop the now-unneeded SECURITY DEFINER function
DROP FUNCTION IF EXISTS _auth_customer_delivery_ids();
