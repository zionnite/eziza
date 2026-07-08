-- Recover visibility for deliveries affected by the bug fixed in
-- 20260708110000: populate bidder_company_auth_ids for every delivery from
-- the company bids that already exist.
UPDATE public.deliveries d SET bidder_company_auth_ids = ARRAY(
  SELECT DISTINCT unnest(COALESCE(d.bidder_company_auth_ids, ARRAY[]::uuid[]) || sub.ids)
)
FROM (
  SELECT db.delivery_id, ARRAY_AGG(DISTINCT c.auth_user_id) AS ids
  FROM public.delivery_bids db
  JOIN public.companies c ON c.id = db.company_id
  WHERE db.company_id IS NOT NULL
  GROUP BY db.delivery_id
) sub
WHERE d.id = sub.delivery_id;
