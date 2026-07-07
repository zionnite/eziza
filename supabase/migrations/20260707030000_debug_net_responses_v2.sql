-- Temporary diagnostic RPC — inspect recent pg_net responses (status +
-- body) to debug the new location-relay trigger. Drop after debugging.
CREATE OR REPLACE FUNCTION public.debug_recent_net_responses_v2(p_limit int DEFAULT 10)
RETURNS TABLE (id bigint, status_code int, created timestamptz, content text)
LANGUAGE sql SECURITY DEFINER AS $$
  SELECT id, status_code, created, content
  FROM net._http_response
  ORDER BY id DESC
  LIMIT p_limit;
$$;

GRANT EXECUTE ON FUNCTION public.debug_recent_net_responses_v2 TO service_role;
