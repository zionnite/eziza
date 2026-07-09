CREATE OR REPLACE FUNCTION public.debug_check_fk_behavior()
RETURNS TABLE(
  child_table text,
  child_column text,
  parent_table text,
  delete_rule text
)
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT
    tc.table_name::text AS child_table,
    kcu.column_name::text AS child_column,
    ccu.table_name::text AS parent_table,
    rc.delete_rule::text AS delete_rule
  FROM information_schema.table_constraints tc
  JOIN information_schema.key_column_usage kcu
    ON tc.constraint_name = kcu.constraint_name AND tc.table_schema = kcu.table_schema
  JOIN information_schema.constraint_column_usage ccu
    ON tc.constraint_name = ccu.constraint_name AND tc.table_schema = ccu.table_schema
  JOIN information_schema.referential_constraints rc
    ON tc.constraint_name = rc.constraint_name AND tc.table_schema = rc.constraint_schema
  WHERE tc.constraint_type = 'FOREIGN KEY'
    AND tc.table_schema = 'public'
    AND ccu.table_name IN ('riders', 'companies', 'customers', 'users')
  ORDER BY ccu.table_name, tc.table_name;
$$;
GRANT EXECUTE ON FUNCTION public.debug_check_fk_behavior() TO service_role;
