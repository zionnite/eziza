-- tenants/api_keys were never locked down like riders/companies/deliveries/customers
-- were in 20260712070000 -- Supabase's default blanket grants left both fully
-- readable/writable by anon and authenticated. Nothing legitimate ever touches
-- these tables except eziza-admin's service-role-only route handlers and the
-- tenant-facing edge functions (also service role, bypasses grants entirely),
-- so this is a pure lockdown with zero functional impact.
REVOKE ALL ON public.tenants FROM anon, authenticated;
REVOKE ALL ON public.api_keys FROM anon, authenticated;
