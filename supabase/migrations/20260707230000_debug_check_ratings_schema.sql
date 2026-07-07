CREATE OR REPLACE FUNCTION public.debug_check_table_columns(p_table text)
RETURNS TABLE(column_name text, data_type text, is_nullable text)
LANGUAGE sql SECURITY DEFINER AS $$
  SELECT column_name, data_type, is_nullable
  FROM information_schema.columns
  WHERE table_schema = 'public' AND table_name = p_table
  ORDER BY ordinal_position;
$$;
