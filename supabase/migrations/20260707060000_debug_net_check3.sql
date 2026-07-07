CREATE OR REPLACE FUNCTION public.debug_net_check3(p_limit int DEFAULT 5)
RETURNS TABLE (id bigint, status_code int, created timestamptz, content text)
LANGUAGE sql SECURITY DEFINER AS $$
  SELECT id, status_code, created, content FROM net._http_response ORDER BY id DESC LIMIT p_limit;
$$;
GRANT EXECUTE ON FUNCTION public.debug_net_check3 TO service_role;
