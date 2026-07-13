-- One login per tenant, mirroring companies.auth_user_id exactly. Nullable
-- since existing tenants (ZeeFashion, Eziza Direct) don't have a login yet --
-- backfilled separately, not by this migration.
ALTER TABLE public.tenants
  ADD COLUMN auth_user_id uuid UNIQUE REFERENCES auth.users(id) ON DELETE SET NULL;
