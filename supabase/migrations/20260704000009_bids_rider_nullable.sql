-- Company bids don't have a rider_id at bid time — rider is assigned after the bid wins.
-- rider_id is only required for individual rider bids.
ALTER TABLE delivery_bids ALTER COLUMN rider_id DROP NOT NULL;
