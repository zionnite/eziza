-- Add lat/lng columns to deliveries so map-picked addresses are stored precisely.
-- Falls back to Nominatim geocoding in map pages if columns are NULL (old deliveries).
ALTER TABLE deliveries
  ADD COLUMN IF NOT EXISTS pickup_lat  double precision,
  ADD COLUMN IF NOT EXISTS pickup_lng  double precision,
  ADD COLUMN IF NOT EXISTS dropoff_lat double precision,
  ADD COLUMN IF NOT EXISTS dropoff_lng double precision;
