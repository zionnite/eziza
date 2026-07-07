CREATE OR REPLACE FUNCTION public.debug_check_deliveries_triggers()
RETURNS TABLE(trigger_name text, event_manipulation text, action_statement text)
LANGUAGE sql SECURITY DEFINER AS $$
  SELECT trigger_name, event_manipulation, action_statement
  FROM information_schema.triggers
  WHERE event_object_table = 'deliveries';
$$;

CREATE OR REPLACE FUNCTION public.debug_check_function_source(p_name text)
RETURNS TABLE(routine_name text, routine_definition text)
LANGUAGE sql SECURITY DEFINER AS $$
  SELECT routine_name, routine_definition
  FROM information_schema.routines
  WHERE routine_name ILIKE p_name AND routine_schema = 'public';
$$;
