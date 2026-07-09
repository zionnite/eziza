-- Lets a customer see a rider's or company's ratings before accepting
-- their bid -- delivery_ratings has no public/general SELECT policy today
-- (only the rater, the ratee, or the ratee's employing company can read
-- their own rows), and widening the raw table RLS to "anyone" would also
-- expose rater_auth_id/rater_name to strangers, which the existing policy
-- deliberately scopes tighter than that. A SECURITY DEFINER RPC gives a
-- narrower, purpose-built read instead: anonymised (no rater identity),
-- rider ratings only (ratee_role is always 'rider' -- riders are never
-- rated as companies, a company's reputation is entirely derived from its
-- fleet's rider ratings, same join used by credit_rider_rating() and the
-- 2026-07-09 company-ratings backfill).
CREATE OR REPLACE FUNCTION public.get_public_ratings(p_ratee_type text, p_ratee_id uuid)
RETURNS TABLE (rater_role text, rating int, comment text, created_at timestamptz)
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT dr.rater_role, dr.rating, dr.comment, dr.created_at
  FROM public.delivery_ratings dr
  WHERE dr.ratee_role = 'rider'
    AND (
      (p_ratee_type = 'rider' AND dr.ratee_id = p_ratee_id)
      OR (p_ratee_type = 'company' AND dr.ratee_id IN (
        SELECT r.id FROM public.riders r
        JOIN public.company_rider_invites cri ON cri.rider_id = r.auth_user_id
        WHERE cri.company_id = p_ratee_id AND cri.status = 'accepted'
      ))
    )
  ORDER BY dr.created_at DESC;
$$;

GRANT EXECUTE ON FUNCTION public.get_public_ratings(text, uuid) TO authenticated;
