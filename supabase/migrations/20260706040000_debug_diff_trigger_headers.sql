-- Temporary diagnostic RPC — locate where our header value diverges from
-- the known-working sibling's, without ever returning either secret.
CREATE OR REPLACE FUNCTION public.debug_diff_trigger_headers()
RETURNS TABLE (
  common_prefix_len int,
  common_suffix_len int,
  ours_length       int,
  sibling_length    int
)
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  ours_def    text;
  sibling_def text;
  ours_hdr    text;
  sibling_hdr text;
  i int;
  prefix_len int := 0;
  suffix_len int := 0;
  min_len int;
BEGIN
  SELECT pg_get_triggerdef(oid) INTO ours_def
  FROM pg_trigger WHERE tgname = 'on_bid_insert_dispatch_tenant_webhook';

  SELECT pg_get_triggerdef(oid) INTO sibling_def
  FROM pg_trigger WHERE tgname = 'on_bid_insert_notify_customer';

  ours_hdr    := (regexp_match(ours_def,    '"Authorization"\s*:\s*"([^"]*)"'))[1];
  sibling_hdr := (regexp_match(sibling_def, '"Authorization"\s*:\s*"([^"]*)"'))[1];

  min_len := LEAST(length(ours_hdr), length(sibling_hdr));

  FOR i IN 1..min_len LOOP
    EXIT WHEN substr(ours_hdr, i, 1) IS DISTINCT FROM substr(sibling_hdr, i, 1);
    prefix_len := i;
  END LOOP;

  FOR i IN 1..min_len LOOP
    EXIT WHEN substr(ours_hdr, length(ours_hdr) - i + 1, 1)
      IS DISTINCT FROM substr(sibling_hdr, length(sibling_hdr) - i + 1, 1);
    suffix_len := i;
  END LOOP;

  RETURN QUERY SELECT prefix_len, suffix_len, length(ours_hdr), length(sibling_hdr);
END;
$$;

GRANT EXECUTE ON FUNCTION public.debug_diff_trigger_headers TO service_role;
