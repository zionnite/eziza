-- Lets a self-service tenant (eziza-partners) flag "I've paid, please credit
-- my balance" without any real payment integration -- same deliberately
-- manual precedent as live_requested_at (a tenant flips this, an admin sees
-- it and acts via the existing Adjust Balance action, nothing here moves
-- money on its own).
ALTER TABLE public.tenants
  ADD COLUMN IF NOT EXISTS topup_requested_at     TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS topup_requested_amount NUMERIC;
