-- Supabase Realtime's postgres_changes authorization is documented to be
-- unreliable when the RLS policy involves a subquery (like the current
-- `rider_id IN (SELECT id FROM riders WHERE auth_user_id = auth.uid())`
-- check on deliveries) — it needs a direct column comparison against
-- auth.uid() to reliably deliver row-change events to a specific client.
-- This is very likely why riders' own realtime subscriptions to their
-- assigned deliveries (used to trigger location broadcasting) have been
-- silently unreliable, despite the same rows being fully readable/writable
-- via direct (RLS-bypassing) queries.

-- Denormalized column, kept in sync automatically whenever rider_id changes.
ALTER TABLE public.deliveries
  ADD COLUMN IF NOT EXISTS rider_auth_user_id UUID;

CREATE OR REPLACE FUNCTION public.sync_deliveries_rider_auth_user_id()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'INSERT' OR NEW.rider_id IS DISTINCT FROM OLD.rider_id THEN
    IF NEW.rider_id IS NULL THEN
      NEW.rider_auth_user_id := NULL;
    ELSE
      SELECT auth_user_id INTO NEW.rider_auth_user_id
      FROM public.riders WHERE id = NEW.rider_id;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_deliveries_rider_auth_user_id ON public.deliveries;
CREATE TRIGGER trg_sync_deliveries_rider_auth_user_id
  BEFORE INSERT OR UPDATE ON public.deliveries
  FOR EACH ROW EXECUTE FUNCTION public.sync_deliveries_rider_auth_user_id();

-- Backfill existing rows.
UPDATE public.deliveries d
SET rider_auth_user_id = r.auth_user_id
FROM public.riders r
WHERE d.rider_id = r.id AND d.rider_auth_user_id IS NULL;

-- Simplify the RLS policy to use the direct column instead of a subquery.
DROP POLICY IF EXISTS deliveries_rider_select ON public.deliveries;
CREATE POLICY deliveries_rider_select ON public.deliveries FOR SELECT
USING (
  status = 'open'
  OR customer_id = auth.uid()
  OR rider_auth_user_id = auth.uid()
  OR id IN (SELECT _auth_company_bid_delivery_ids())
);
