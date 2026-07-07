CREATE OR REPLACE FUNCTION public.debug_check_constraint_def(p_name text)
RETURNS text
LANGUAGE sql SECURITY DEFINER AS $$
  SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname = p_name;
$$;
GRANT EXECUTE ON FUNCTION public.debug_check_constraint_def(text) TO service_role;
