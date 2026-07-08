-- The previous migration's column-scoped GRANT UPDATE (pin, pin_set, ...)
-- was a no-op: Supabase's default privileges already grant `authenticated`
-- a blanket table-level UPDATE (all columns) on every new table, and GRANT
-- is purely additive in Postgres — a narrower grant never overrides a
-- broader pre-existing one. Confirmed empirically: a raw client PATCH
-- setting wallet_balance directly succeeded despite the "restricted" grant.
-- REVOKE the blanket privilege first, then re-grant only the columns a
-- customer should ever be able to touch directly. wallet_balance must only
-- ever move via the wallet_transactions trigger.
REVOKE UPDATE ON public.customers FROM authenticated;
GRANT UPDATE (pin, pin_set, full_name, phone, avatar_url) ON public.customers TO authenticated;
