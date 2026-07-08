-- Phase 4: transaction PIN — mirrors ZeeFashion's plaintext-storage pattern
-- (profiles.pin / profiles.pin_set) per the roadmap's explicit note to
-- match it unless told otherwise. pin_set is a proper BOOLEAN here rather
-- than ZeeFashion's TEXT 'yes' flag — that's just cleaner typing, not a
-- deviation from the plaintext-PIN behavior itself.
ALTER TABLE public.customers
  ADD COLUMN IF NOT EXISTS pin     TEXT,
  ADD COLUMN IF NOT EXISTS pin_set BOOLEAN NOT NULL DEFAULT false;

-- Customers can update their own profile fields — but NOT wallet_balance,
-- which must only ever move via the wallet_transactions trigger. Column-
-- level GRANT enforces this independently of the RLS row policy: even a
-- crafted PATCH targeting wallet_balance would be rejected at the SQL
-- layer before RLS is even evaluated.
GRANT UPDATE (pin, pin_set, full_name, phone, avatar_url) ON public.customers TO authenticated;

CREATE POLICY customers_update_own ON public.customers FOR UPDATE
USING (id = auth.uid())
WITH CHECK (id = auth.uid());
