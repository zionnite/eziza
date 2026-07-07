CREATE OR REPLACE FUNCTION public.debug_find_trigger_by_function(p_func text)
RETURNS TABLE(trigger_name text, event_object_table text, event_manipulation text)
LANGUAGE sql SECURITY DEFINER AS $$
  SELECT trigger_name, event_object_table, event_manipulation
  FROM information_schema.triggers
  WHERE action_statement ILIKE '%' || p_func || '%';
$$;

CREATE OR REPLACE FUNCTION public.debug_get_function_body(p_name text)
RETURNS text
LANGUAGE sql SECURITY DEFINER AS $$
  SELECT pg_get_functiondef(oid) FROM pg_proc WHERE proname = p_name LIMIT 1;
$$;
