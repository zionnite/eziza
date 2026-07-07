-- Temporary diagnostic RPC — check whether pg_net actually attempted the
-- outbound HTTP call from the trigger, and what status came back. Drop
-- after debugging. Response bodies/headers are excluded to avoid ever
-- surfacing secrets that may appear in error text.
CREATE OR REPLACE FUNCTION public.debug_recent_net_responses()
RETURNS TABLE (id bigint, status_code int, created timestamptz, "timed_out" boolean, error_msg text)
LANGUAGE sql SECURITY DEFINER AS $$
  SELECT id, status_code, created, timed_out, error_msg
  FROM net._http_response
  ORDER BY id DESC
  LIMIT 10;
$$;

GRANT EXECUTE ON FUNCTION public.debug_recent_net_responses TO service_role;
