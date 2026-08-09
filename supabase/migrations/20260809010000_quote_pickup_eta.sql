-- Shipbubble returns pickup_eta alongside delivery_eta on every quote, but
-- only delivery_eta had a column -- pickup_eta was silently dropped after
-- fetch_rates, even though ZeeFashion wanted to show "how long until
-- pickup" (2026-08-09) and there was nowhere to persist it past the raw
-- Shipbubble response.
ALTER TABLE public.external_carrier_quotes
  ADD COLUMN IF NOT EXISTS pickup_eta text;
