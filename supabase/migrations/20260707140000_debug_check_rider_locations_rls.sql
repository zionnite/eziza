CREATE OR REPLACE FUNCTION public.debug_check_policies(p_table text)
RETURNS TABLE (policyname text, cmd text, qual text, with_check text)
LANGUAGE sql SECURITY DEFINER AS $$
  SELECT policyname::text, cmd::text, qual::text, with_check::text
  FROM pg_policies
  WHERE tablename = p_table;
$$;
GRANT EXECUTE ON FUNCTION public.debug_check_policies(text) TO service_role;
