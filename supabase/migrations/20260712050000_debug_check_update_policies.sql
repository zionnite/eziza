CREATE OR REPLACE FUNCTION public.debug_check_update_policies(p_table text)
RETURNS TABLE(policyname text, qual text, with_check text)
LANGUAGE sql SECURITY DEFINER AS $$
  SELECT policyname, qual, with_check
  FROM pg_policies
  WHERE tablename = p_table AND cmd = 'UPDATE';
$$;
