CREATE OR REPLACE FUNCTION public.debug_get_function_body(p_name text)
RETURNS text
LANGUAGE sql SECURITY DEFINER AS $$
  SELECT pg_get_functiondef(oid) FROM pg_proc WHERE proname = p_name LIMIT 1;
$$;
