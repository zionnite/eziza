CREATE OR REPLACE FUNCTION public.debug_search_function_refs(p_needle text)
RETURNS TABLE(routine_name text, matches boolean)
LANGUAGE sql SECURITY DEFINER AS $$
  SELECT routine_name, (routine_definition ILIKE '%' || p_needle || '%')
  FROM information_schema.routines
  WHERE routine_schema = 'public' AND routine_definition ILIKE '%' || p_needle || '%';
$$;
