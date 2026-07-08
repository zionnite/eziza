-- Phase 3: deliveries previously had no payment step at all — accepting a
-- bid just set status='assigned' with no money moving from the customer.
ALTER TABLE public.deliveries
  ADD COLUMN IF NOT EXISTS payment_source TEXT,               -- 'wallet' (only source for now)
  ADD COLUMN IF NOT EXISTS payment_ref    TEXT,
  ADD COLUMN IF NOT EXISTS payment_status TEXT NOT NULL DEFAULT 'unpaid';
