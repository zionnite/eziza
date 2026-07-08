CREATE OR REPLACE FUNCTION public.debug_list_triggers(p_table text)
RETURNS TABLE(trigger_name text, event_manipulation text, action_timing text, function_name text)
LANGUAGE sql SECURITY DEFINER AS $$
  SELECT t.tgname::text,
         CASE t.tgtype & 28
           WHEN 4 THEN 'INSERT' WHEN 8 THEN 'DELETE'
           WHEN 16 THEN 'UPDATE' ELSE 'MULTI' END,
         CASE WHEN t.tgtype & 2 > 0 THEN 'BEFORE' ELSE 'AFTER' END,
         p.proname::text
  FROM pg_trigger t
  JOIN pg_proc p ON p.oid = t.tgfoid
  JOIN pg_class c ON c.oid = t.tgrelid
  WHERE c.relname = p_table AND NOT t.tgisinternal;
$$;

CREATE OR REPLACE FUNCTION public.debug_get_function_body(p_name text)
RETURNS text
LANGUAGE sql SECURITY DEFINER AS $$
  SELECT pg_get_functiondef(oid) FROM pg_proc WHERE proname = p_name LIMIT 1;
$$;
