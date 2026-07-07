CREATE OR REPLACE FUNCTION public.debug_check_customer_update_qual(p_delivery_id uuid, p_auth_uid uuid)
RETURNS TABLE(matches boolean, customer_id uuid, delivery_status text)
LANGUAGE sql SECURITY DEFINER AS $$
  SELECT (customer_id = p_auth_uid), customer_id, status
  FROM deliveries WHERE id = p_delivery_id;
$$;

CREATE OR REPLACE FUNCTION public.debug_list_deliveries_policies()
RETURNS TABLE(policyname text, cmd text, qual text, with_check text)
LANGUAGE sql SECURITY DEFINER AS $$
  SELECT policyname, cmd, qual, with_check
  FROM pg_policies
  WHERE tablename = 'deliveries';
$$;
