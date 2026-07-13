-- Sandbox mode: self-signup tenants land here automatically, an admin
-- promotes to live. Real riders must never see or bid on sandbox
-- deliveries, so is_sandbox is denormalized onto deliveries (and riders,
-- for the synthetic sandbox riders below) rather than derived via a join --
-- same lesson as the realtime RLS denormalizations earlier in this project:
-- direct column comparisons are required for reliability.

ALTER TABLE public.tenants
  ADD COLUMN mode text NOT NULL DEFAULT 'sandbox'
    CHECK (mode IN ('sandbox', 'live'));

-- Both existing tenants are real, already-flowing production traffic.
UPDATE public.tenants SET mode = 'live';

ALTER TABLE public.deliveries
  ADD COLUMN is_sandbox boolean NOT NULL DEFAULT false;

ALTER TABLE public.riders
  ADD COLUMN is_sandbox boolean NOT NULL DEFAULT false;

-- Synthetic riders standing in for real ones on sandbox deliveries.
-- auth_user_id is nullable -- these never need a real login. is_approved/
-- status are set so they pass the same checks a real approved rider would.
INSERT INTO public.riders (full_name, phone, vehicle_type, is_approved, status, is_sandbox)
VALUES
  ('Sandbox Rider One', '0000000001', 'bike', true, 'approved', true),
  ('Sandbox Rider Two', '0000000002', 'bike', true, 'approved', true);
