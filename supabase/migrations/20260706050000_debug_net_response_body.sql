-- Temporary diagnostic RPC — inspect the actual response body pg_net
-- received from the tenant webhook call, to debug why a downstream field
-- update didn't take effect despite a 200 response. Drop after debugging.
CREATE OR REPLACE FUNCTION public.debug_recent_net_response_body(p_id bigint)
RETURNS TABLE (id bigint, status_code int, content text)
LANGUAGE sql SECURITY DEFINER AS $$
  SELECT id, status_code, content
  FROM net._http_response
  WHERE id = p_id;
$$;

GRANT EXECUTE ON FUNCTION public.debug_recent_net_response_body TO service_role;
