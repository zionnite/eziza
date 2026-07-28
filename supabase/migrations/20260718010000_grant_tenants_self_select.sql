-- 20260713020000_tenants_self_select_policy.sql added the tenants_self_select
-- RLS policy so a logged-in tenant could read their own row, but the prior
-- migration (20260713000000) had REVOKEd all privileges on tenants from
-- authenticated -- RLS never overrides a missing base GRANT, so the policy
-- was dead code: every eziza-partners login failed at
-- "This account does not have partner portal access." regardless of the
-- policy being correct. Narrow SELECT-only grant, matching the policy's own
-- scope -- writes to tenants still go through service-role Route Handlers only.
GRANT SELECT ON public.tenants TO authenticated;
