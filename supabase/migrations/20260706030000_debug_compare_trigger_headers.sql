-- Temporary diagnostic RPC — compare the Authorization header value embedded
-- in our new trigger against the known-working sibling trigger's value,
-- WITHOUT ever returning either secret. Drop after debugging.
CREATE OR REPLACE FUNCTION public.debug_compare_trigger_headers()
RETURNS TABLE (
  ours_length      int,
  sibling_length   int,
  values_equal     boolean,
  ours_has_bearer_bearer boolean,
  ours_starts_with_bearer_space boolean
)
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  ours_def    text;
  sibling_def text;
  ours_hdr    text;
  sibling_hdr text;
BEGIN
  SELECT pg_get_triggerdef(oid) INTO ours_def
  FROM pg_trigger WHERE tgname = 'on_bid_insert_dispatch_tenant_webhook';

  SELECT pg_get_triggerdef(oid) INTO sibling_def
  FROM pg_trigger WHERE tgname = 'on_bid_insert_notify_customer';

  -- Extract the value of the "Authorization" key from the headers JSON arg
  ours_hdr    := (regexp_match(ours_def,    '"Authorization"\s*:\s*"([^"]*)"'))[1];
  sibling_hdr := (regexp_match(sibling_def, '"Authorization"\s*:\s*"([^"]*)"'))[1];

  RETURN QUERY SELECT
    length(ours_hdr),
    length(sibling_hdr),
    ours_hdr = sibling_hdr,
    ours_hdr LIKE '%Bearer Bearer%',
    ours_hdr LIKE 'Bearer %';
END;
$$;

GRANT EXECUTE ON FUNCTION public.debug_compare_trigger_headers TO service_role;
