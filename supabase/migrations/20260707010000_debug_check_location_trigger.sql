-- Temporary diagnostic RPC — confirm the new location-relay trigger's
-- Authorization header was actually updated from the placeholder. Drop
-- after debugging.
CREATE OR REPLACE FUNCTION public.debug_check_location_trigger()
RETURNS TABLE (trigger_name text, enabled text, has_placeholder_jwt boolean)
LANGUAGE sql SECURITY DEFINER AS $$
  SELECT tgname::text, tgenabled::text, pg_get_triggerdef(oid) LIKE '%<SERVICE_ROLE_JWT>%'
  FROM pg_trigger
  WHERE tgname = 'on_rider_location_dispatch_tenant_webhook';
$$;

GRANT EXECUTE ON FUNCTION public.debug_check_location_trigger TO service_role;
