-- Temporary diagnostic RPC — compare the new location trigger's
-- Authorization header against a known-working sibling, without ever
-- returning either secret. Drop after debugging.
CREATE OR REPLACE FUNCTION public.debug_compare_location_trigger()
RETURNS TABLE (ours_length int, sibling_length int, values_equal boolean)
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  ours_def    text;
  sibling_def text;
  ours_hdr    text;
  sibling_hdr text;
BEGIN
  SELECT pg_get_triggerdef(oid) INTO ours_def
  FROM pg_trigger WHERE tgname = 'on_rider_location_dispatch_tenant_webhook';

  SELECT pg_get_triggerdef(oid) INTO sibling_def
  FROM pg_trigger WHERE tgname = 'on_bid_insert_dispatch_tenant_webhook';

  ours_hdr    := (regexp_match(ours_def,    '"Authorization"\s*:\s*"([^"]*)"'))[1];
  sibling_hdr := (regexp_match(sibling_def, '"Authorization"\s*:\s*"([^"]*)"'))[1];

  RETURN QUERY SELECT length(ours_hdr), length(sibling_hdr), ours_hdr = sibling_hdr;
END;
$$;

GRANT EXECUTE ON FUNCTION public.debug_compare_location_trigger TO service_role;
