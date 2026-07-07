-- Redesign delivery_ratings for a multi-party, multi-checkpoint model.
-- The old shape (rider_rating/customer_rating/rider_comment/customer_comment)
-- conflated "customer" into one slot, but a delivery has up to two distinct
-- customer-side people: the sender (deliveries.customer_id) and the receiver
-- (deliveries.recipient_auth_id, nullable — only set when explicitly claimed;
-- otherwise the sender is also the de facto receiver). Table has 0 rows and
-- is unreferenced anywhere in the codebase — safe to replace outright.

DROP TABLE IF EXISTS public.delivery_ratings;

CREATE TABLE public.delivery_ratings (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  delivery_id   UUID NOT NULL REFERENCES public.deliveries(id) ON DELETE CASCADE,
  checkpoint    TEXT NOT NULL CHECK (checkpoint IN ('handoff', 'delivery')),
  rater_auth_id UUID NOT NULL,
  rater_role    TEXT NOT NULL CHECK (rater_role IN ('rider', 'sender', 'receiver')),
  rater_name    TEXT,
  ratee_role    TEXT NOT NULL CHECK (ratee_role IN ('rider', 'sender', 'receiver')),
  ratee_id      UUID,
  rating        INT NOT NULL CHECK (rating BETWEEN 1 AND 5),
  comment       TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (delivery_id, checkpoint, rater_role)
);

CREATE INDEX idx_delivery_ratings_ratee ON public.delivery_ratings(ratee_id);
CREATE INDEX idx_delivery_ratings_delivery ON public.delivery_ratings(delivery_id);

ALTER TABLE public.riders ADD COLUMN IF NOT EXISTS rating_count INTEGER NOT NULL DEFAULT 0;

-- Aggregate into riders.rating_avg/rating_count whenever a rider is rated.
CREATE OR REPLACE FUNCTION public.credit_rider_rating()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.ratee_role = 'rider' AND NEW.ratee_id IS NOT NULL THEN
    UPDATE public.riders SET
      rating_avg   = ((rating_avg * rating_count) + NEW.rating) / (rating_count + 1),
      rating_count = rating_count + 1
    WHERE id = NEW.ratee_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_credit_rider_rating ON public.delivery_ratings;
CREATE TRIGGER trg_credit_rider_rating
  AFTER INSERT ON public.delivery_ratings
  FOR EACH ROW EXECUTE FUNCTION public.credit_rider_rating();

ALTER TABLE public.delivery_ratings ENABLE ROW LEVEL SECURITY;

-- SELECT: your own submitted ratings, ratings about you (rider), or —
-- for companies — ratings about riders linked to you via an accepted invite.
CREATE POLICY delivery_ratings_select ON public.delivery_ratings FOR SELECT
USING (
  rater_auth_id = auth.uid()
  OR ratee_id IN (SELECT id FROM public.riders WHERE auth_user_id = auth.uid())
  OR ratee_id IN (
       SELECT r.id FROM public.riders r
       JOIN public.company_rider_invites cri ON cri.rider_id = r.auth_user_id
       JOIN public.companies c ON c.id = cri.company_id
       WHERE cri.status = 'accepted' AND c.auth_user_id = auth.uid()
     )
);

-- INSERT: rider can rate on a delivery they're assigned to; sender can rate
-- on a delivery they created; receiver can rate if they're the claimed
-- recipient, or — when no distinct recipient was ever claimed — the sender
-- acting as the de facto receiver.
CREATE POLICY delivery_ratings_insert ON public.delivery_ratings FOR INSERT
WITH CHECK (
  rater_auth_id = auth.uid()
  AND (
    (rater_role = 'rider' AND EXISTS (
      SELECT 1 FROM public.deliveries d
      WHERE d.id = delivery_id AND d.rider_auth_user_id = auth.uid()
    ))
    OR (rater_role = 'sender' AND EXISTS (
      SELECT 1 FROM public.deliveries d
      WHERE d.id = delivery_id AND d.customer_id = auth.uid()
    ))
    OR (rater_role = 'receiver' AND EXISTS (
      SELECT 1 FROM public.deliveries d
      WHERE d.id = delivery_id
        AND (d.recipient_auth_id = auth.uid()
             OR (d.recipient_auth_id IS NULL AND d.customer_id = auth.uid()))
    ))
  )
);
