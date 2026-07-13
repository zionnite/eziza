-- Real riders must never see sandbox deliveries on the open job board.
-- Both policies' "any open delivery is visible" branch needs is_sandbox
-- excluded -- the "it's mine" branches don't need touching since a real
-- rider's auth_user_id can never match a synthetic sandbox rider's
-- (auth_user_id is NULL for those).

ALTER POLICY deliveries_rider_select ON public.deliveries
  USING (
    (status = 'open' AND is_sandbox = false)
    OR (customer_id = auth.uid())
    OR (rider_auth_user_id = auth.uid())
    OR (auth.uid() = ANY (bidder_company_auth_ids))
  );

ALTER POLICY riders_see_deliveries ON public.deliveries
  USING (
    (status = 'open' AND is_sandbox = false)
    OR (rider_id = (SELECT riders.id FROM riders WHERE riders.auth_user_id = auth.uid()))
  );
