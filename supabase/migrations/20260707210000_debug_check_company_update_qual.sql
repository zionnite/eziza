CREATE OR REPLACE FUNCTION public.debug_check_company_update_qual(p_delivery_id uuid, p_auth_uid uuid)
RETURNS TABLE(matches boolean, bid_id uuid, bid_status text, bid_company_id uuid, company_auth_user_id uuid)
LANGUAGE sql SECURITY DEFINER AS $$
  SELECT
    EXISTS (
      SELECT 1 FROM delivery_bids db
      JOIN companies c ON c.id = db.company_id
      WHERE db.delivery_id = p_delivery_id
        AND c.auth_user_id = p_auth_uid
        AND db.status = 'accepted'
    ),
    db.id, db.status, db.company_id, c.auth_user_id
  FROM delivery_bids db
  LEFT JOIN companies c ON c.id = db.company_id
  WHERE db.delivery_id = p_delivery_id;
$$;
