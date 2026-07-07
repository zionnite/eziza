-- Temporary diagnostic RPC — inspect delivery_bids triggers without needing
-- direct psql/DB-password access, and WITHOUT ever surfacing the trigger's
-- Authorization header value (which contains a live secret). Drop this
-- after debugging.
CREATE OR REPLACE FUNCTION public.debug_check_bid_triggers()
RETURNS TABLE (trigger_name text, enabled text, has_placeholder_jwt boolean, def_length int)
LANGUAGE sql SECURITY DEFINER AS $$
  SELECT
    tgname::text,
    tgenabled::text,
    pg_get_triggerdef(oid) LIKE '%<SERVICE_ROLE_JWT>%',
    length(pg_get_triggerdef(oid))
  FROM pg_trigger
  WHERE tgrelid = 'public.delivery_bids'::regclass AND NOT tgisinternal;
$$;

GRANT EXECUTE ON FUNCTION public.debug_check_bid_triggers TO service_role;
