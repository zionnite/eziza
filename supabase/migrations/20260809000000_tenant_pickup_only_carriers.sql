-- Some tenants don't want their buyers offered "dropoff" couriers -- the
-- merchant would have to personally take the package to a courier station,
-- which isn't how they operate. Per-tenant setting (not hardcoded in
-- application code) since other tenants may be fine with dropoff options.
ALTER TABLE public.tenants
  ADD COLUMN pickup_only_carriers boolean NOT NULL DEFAULT false;

-- ZeeFashion, confirmed 2026-08-09: riders/couriers must come to the
-- vendor's own location, never a drop-off station.
UPDATE public.tenants
  SET pickup_only_carriers = true
  WHERE id = 'd0640c99-5613-41f5-aa36-597cbb6ad023';
