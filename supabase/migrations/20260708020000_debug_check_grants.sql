CREATE OR REPLACE FUNCTION public.debug_check_grants(p_table text)
RETURNS TABLE(grantee text, privilege_type text)
LANGUAGE sql SECURITY DEFINER AS $$
  SELECT grantee, privilege_type FROM information_schema.role_table_grants
  WHERE table_name = p_table AND table_schema = 'public';
$$;
