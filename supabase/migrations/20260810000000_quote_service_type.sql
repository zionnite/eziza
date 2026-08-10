-- Shipbubble returns service_type ('pickup' | 'dropoff') on every courier
-- quote -- already used to filter ZeeFashion's own quotes
-- (tenants.pickup_only_carriers), but never stored/surfaced to the
-- customer picking a courier directly. Needed so the picker can show
-- "rider comes to you" vs "you drop off at a station" per quote.
ALTER TABLE public.external_carrier_quotes
  ADD COLUMN IF NOT EXISTS service_type text;
