CREATE OR REPLACE FUNCTION public.debug_check_realtime_pub(p_table text)
RETURNS boolean
LANGUAGE sql SECURITY DEFINER AS $$
  SELECT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = p_table
  );
$$;
GRANT EXECUTE ON FUNCTION public.debug_check_realtime_pub(text) TO service_role;
