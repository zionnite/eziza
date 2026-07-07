-- Same class of bug as credit_delivery_earnings(): credit_rider_rating()
-- updates riders.rating_avg/rating_count as the rater's own session, but the
-- riders UPDATE policy only allows a rider to update their own row
-- (auth_user_id = auth.uid()). A customer rating a rider satisfies that
-- policy for nobody, so the UPDATE silently affected 0 rows — no error, but
-- the aggregate never moved and the rider's Rating tab stayed empty.
ALTER FUNCTION public.credit_rider_rating() SECURITY DEFINER SET search_path = public;
