CREATE OR REPLACE FUNCTION public.debug_check_constraints(p_table text)
RETURNS TABLE(conname text, definition text)
LANGUAGE sql SECURITY DEFINER AS $$
  SELECT c.conname::text, pg_get_constraintdef(c.oid)
  FROM pg_constraint c
  JOIN pg_class t ON t.oid = c.conrelid
  WHERE t.relname = p_table AND c.contype = 'c';
$$;
