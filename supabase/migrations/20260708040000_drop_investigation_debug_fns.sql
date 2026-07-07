-- Clean up debug introspection functions used to diagnose the
-- credit_delivery_earnings() RLS/SECURITY DEFINER bug.
DROP FUNCTION IF EXISTS public.debug_get_function_body(text);
DROP FUNCTION IF EXISTS public.debug_check_table_rls(text);
DROP FUNCTION IF EXISTS public.debug_check_grants(text);
