-- rider_application_page.dart offers 5 vehicle type options (bike, bicycle,
-- car, van, foot), but the DB constraint only allowed 4 different ones
-- (bike, car, van, truck) — missing 'bicycle' and 'foot', which the app
-- actually submits. Selecting either in the registration form fails with
-- a check constraint violation. Widen the constraint to match what the
-- app offers (keeping 'truck' too, in case anything else relies on it).
ALTER TABLE public.riders DROP CONSTRAINT IF EXISTS riders_vehicle_type_check;
ALTER TABLE public.riders ADD CONSTRAINT riders_vehicle_type_check
  CHECK (vehicle_type = ANY (ARRAY['bike', 'bicycle', 'car', 'van', 'foot', 'truck']));
