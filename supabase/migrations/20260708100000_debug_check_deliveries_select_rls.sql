CREATE OR REPLACE FUNCTION public.debug_check_table_rls(p_table text)
RETURNS TABLE(relrowsecurity boolean, policyname text, cmd text, qual text, with_check text)
LANGUAGE sql SECURITY DEFINER AS $$
  SELECT c.relrowsecurity, p.policyname, p.cmd, p.qual, p.with_check
  FROM pg_class c
  LEFT JOIN pg_policies p ON p.tablename = c.relname
  WHERE c.relname = p_table;
$$;
