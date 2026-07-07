-- Recover ratings silently dropped by the credit_rider_rating() bug fixed in
-- 20260708060000: recompute rating_avg/rating_count for every rider from the
-- delivery_ratings rows that already exist.
UPDATE public.riders r SET
  rating_avg   = sub.avg_rating,
  rating_count = sub.cnt
FROM (
  SELECT ratee_id, AVG(rating)::numeric AS avg_rating, COUNT(*) AS cnt
  FROM public.delivery_ratings
  WHERE ratee_role = 'rider' AND ratee_id IS NOT NULL
  GROUP BY ratee_id
) sub
WHERE r.id = sub.ratee_id;
