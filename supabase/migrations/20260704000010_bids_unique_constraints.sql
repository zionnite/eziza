-- Required for upsert onConflict to work when re-bidding on the same delivery.
-- rider_id is nullable so the rider constraint uses a partial index (WHERE rider_id IS NOT NULL).
ALTER TABLE delivery_bids
  ADD CONSTRAINT delivery_bids_delivery_company_unique UNIQUE (delivery_id, company_id);

CREATE UNIQUE INDEX IF NOT EXISTS delivery_bids_delivery_rider_unique
  ON delivery_bids (delivery_id, rider_id)
  WHERE rider_id IS NOT NULL;
