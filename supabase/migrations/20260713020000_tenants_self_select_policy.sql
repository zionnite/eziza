-- tenants has RLS enabled with zero policies, so a legitimately-linked
-- tenant user querying their own row via the anon key (eziza-partners'
-- login/auth-check, both client-side) would get nothing back -- RLS with
-- no policy defaults to deny-all regardless of auth_user_id matching.
-- Self-select-only, mirroring admin_profiles' own pattern; every other
-- operation on tenants still goes through eziza-admin/eziza-partners'
-- service-role Route Handlers.
CREATE POLICY tenants_self_select ON public.tenants
  FOR SELECT
  USING (auth_user_id = auth.uid());
