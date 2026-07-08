-- Phase 2 (eziza-admin): admin auth gating table, same shape/pattern as
-- ZeeFashion admin's admin_profiles (id references auth.users, is_active
-- flag checked on every login and on every dashboard layout mount).
CREATE TABLE IF NOT EXISTS public.admin_profiles (
  id         UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email      TEXT,
  full_name  TEXT,
  is_active  BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.admin_profiles ENABLE ROW LEVEL SECURITY;

-- Only used by the login/auth-gate check (anon key, caller's own row) —
-- every other admin operation goes through server-side Route Handlers using
-- the service-role key, never the browser.
CREATE POLICY admin_profiles_select_own ON public.admin_profiles FOR SELECT
USING (id = auth.uid());
