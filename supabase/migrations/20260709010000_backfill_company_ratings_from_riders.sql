-- Recover company ratings dropped before the fix in 20260709000000:
-- recompute companies.rating_avg/rating_count from delivery_ratings rows
-- against riders with an accepted company_rider_invites row.
UPDATE public.companies c SET
  rating_avg   = sub.avg_rating,
  rating_count = sub.cnt
FROM (
  SELECT cri.company_id, AVG(dr.rating)::numeric AS avg_rating, COUNT(*) AS cnt
  FROM public.delivery_ratings dr
  JOIN public.riders r ON r.id = dr.ratee_id
  JOIN public.company_rider_invites cri
    ON cri.rider_id = r.auth_user_id AND cri.status = 'accepted'
  WHERE dr.ratee_role = 'rider'
  GROUP BY cri.company_id
) sub
WHERE c.id = sub.company_id;
