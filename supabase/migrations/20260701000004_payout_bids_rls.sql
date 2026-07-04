-- Add status to delivery_bids (tracks pending/accepted/rejected)
ALTER TABLE delivery_bids ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'pending';

-- Rider payout requests
CREATE TABLE IF NOT EXISTS rider_payout_requests (
  id           UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  rider_id     UUID REFERENCES riders(id) ON DELETE CASCADE NOT NULL,
  amount       NUMERIC NOT NULL CHECK (amount > 0),
  status       TEXT NOT NULL DEFAULT 'pending',
  requested_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  processed_at TIMESTAMPTZ
);

-- RLS: deliveries — riders see open deliveries + deliveries assigned to them
ALTER TABLE deliveries ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='deliveries' AND policyname='deliveries_rider_select') THEN
    CREATE POLICY deliveries_rider_select ON deliveries FOR SELECT
    USING (
      status = 'open'
      OR rider_id IN (SELECT id FROM riders WHERE auth_user_id = auth.uid())
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='deliveries' AND policyname='deliveries_rider_update') THEN
    CREATE POLICY deliveries_rider_update ON deliveries FOR UPDATE
    USING (rider_id IN (SELECT id FROM riders WHERE auth_user_id = auth.uid()));
  END IF;
END $$;

-- RLS: delivery_bids — riders manage their own bids
ALTER TABLE delivery_bids ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='delivery_bids' AND policyname='bids_rider_select') THEN
    CREATE POLICY bids_rider_select ON delivery_bids FOR SELECT
    USING (rider_id IN (SELECT id FROM riders WHERE auth_user_id = auth.uid()));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='delivery_bids' AND policyname='bids_rider_insert') THEN
    CREATE POLICY bids_rider_insert ON delivery_bids FOR INSERT
    WITH CHECK (rider_id IN (SELECT id FROM riders WHERE auth_user_id = auth.uid()));
  END IF;
END $$;

-- RLS: company_rider_invites — riders read/respond to their own invites
ALTER TABLE company_rider_invites ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='company_rider_invites' AND policyname='invites_rider_select') THEN
    CREATE POLICY invites_rider_select ON company_rider_invites FOR SELECT
    USING (rider_id = auth.uid());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='company_rider_invites' AND policyname='invites_rider_update') THEN
    CREATE POLICY invites_rider_update ON company_rider_invites FOR UPDATE
    USING (rider_id = auth.uid());
  END IF;
END $$;

-- RLS: rider_payout_requests — riders manage their own payout requests
ALTER TABLE rider_payout_requests ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='rider_payout_requests' AND policyname='payout_rider_select') THEN
    CREATE POLICY payout_rider_select ON rider_payout_requests FOR SELECT
    USING (rider_id IN (SELECT id FROM riders WHERE auth_user_id = auth.uid()));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='rider_payout_requests' AND policyname='payout_rider_insert') THEN
    CREATE POLICY payout_rider_insert ON rider_payout_requests FOR INSERT
    WITH CHECK (rider_id IN (SELECT id FROM riders WHERE auth_user_id = auth.uid()));
  END IF;
END $$;
