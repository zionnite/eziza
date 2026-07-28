-- deliveries_tenant_external_idx was a plain UNIQUE (tenant_id, external_order_id)
-- with no exclusion for dead rows -- once a tenant had ANY delivery for a given
-- external_order_id, even one already 'cancelled', create-delivery would 500
-- with a duplicate-key violation on every future attempt for that same order,
-- forever. Found live: ZeeFashion's own "Request Pickup Again" retry (built to
-- recover from exactly this kind of failure) hit this immediately on its first
-- real retry. The constraint's actual intent -- stop a tenant from having two
-- simultaneously-live deliveries for one order -- doesn't require blocking a
-- fresh attempt after the old one is dead. Made partial so cancelled rows no
-- longer count toward the uniqueness check.
DROP INDEX IF EXISTS public.deliveries_tenant_external_idx;

CREATE UNIQUE INDEX deliveries_tenant_external_idx
  ON public.deliveries (tenant_id, external_order_id)
  WHERE status != 'cancelled';
