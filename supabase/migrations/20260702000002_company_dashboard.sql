-- Companies bid on deliveries: add company_id to delivery_bids (nullable — rider bids leave it null)
ALTER TABLE delivery_bids ADD COLUMN IF NOT EXISTS company_id UUID REFERENCES companies(id) ON DELETE CASCADE;

-- Company payout requests
CREATE TABLE IF NOT EXISTS company_payout_requests (
  id           UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  company_id   UUID REFERENCES companies(id) ON DELETE CASCADE NOT NULL,
  amount       NUMERIC NOT NULL CHECK (amount > 0),
  status       TEXT    NOT NULL DEFAULT 'pending',
  requested_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  processed_at TIMESTAMPTZ
);
ALTER TABLE company_payout_requests ENABLE ROW LEVEL SECURITY;

-- ── RLS ────────────────────────────────────────────────────────────────────────

-- Companies: owner reads/updates their own row
ALTER TABLE companies ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='companies' AND policyname='companies_owner_select') THEN
    CREATE POLICY companies_owner_select ON companies FOR SELECT USING (auth_user_id = auth.uid());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='companies' AND policyname='companies_owner_update') THEN
    CREATE POLICY companies_owner_update ON companies FOR UPDATE USING (auth_user_id = auth.uid());
  END IF;
END $$;

-- Company payout requests
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='company_payout_requests' AND policyname='co_payout_select') THEN
    CREATE POLICY co_payout_select ON company_payout_requests FOR SELECT
    USING (company_id IN (SELECT id FROM companies WHERE auth_user_id = auth.uid()));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='company_payout_requests' AND policyname='co_payout_insert') THEN
    CREATE POLICY co_payout_insert ON company_payout_requests FOR INSERT
    WITH CHECK (company_id IN (SELECT id FROM companies WHERE auth_user_id = auth.uid()));
  END IF;
END $$;

-- delivery_bids: company can select / insert / update their own bids
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='delivery_bids' AND policyname='bids_company_select') THEN
    CREATE POLICY bids_company_select ON delivery_bids FOR SELECT
    USING (company_id IN (SELECT id FROM companies WHERE auth_user_id = auth.uid()));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='delivery_bids' AND policyname='bids_company_insert') THEN
    CREATE POLICY bids_company_insert ON delivery_bids FOR INSERT
    WITH CHECK (company_id IN (SELECT id FROM companies WHERE auth_user_id = auth.uid()));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='delivery_bids' AND policyname='bids_company_update') THEN
    CREATE POLICY bids_company_update ON delivery_bids FOR UPDATE
    USING (company_id IN (SELECT id FROM companies WHERE auth_user_id = auth.uid()));
  END IF;
END $$;

-- company_rider_invites: company can select / insert their own invites
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='company_rider_invites' AND policyname='invites_company_select') THEN
    CREATE POLICY invites_company_select ON company_rider_invites FOR SELECT
    USING (company_id IN (SELECT id FROM companies WHERE auth_user_id = auth.uid()));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='company_rider_invites' AND policyname='invites_company_insert') THEN
    CREATE POLICY invites_company_insert ON company_rider_invites FOR INSERT
    WITH CHECK (company_id IN (SELECT id FROM companies WHERE auth_user_id = auth.uid()));
  END IF;
END $$;

-- deliveries SELECT: extend to include company users who have a bid on the delivery
DROP POLICY IF EXISTS deliveries_rider_select ON deliveries;
CREATE POLICY deliveries_rider_select ON deliveries FOR SELECT
USING (
  status = 'open'
  OR rider_id IN (SELECT id FROM riders WHERE auth_user_id = auth.uid())
  OR id IN (
    SELECT db.delivery_id FROM delivery_bids db
    INNER JOIN companies c ON c.id = db.company_id
    WHERE c.auth_user_id = auth.uid()
  )
);

-- deliveries UPDATE: company can update deliveries they won (to assign a rider)
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='deliveries' AND policyname='deliveries_company_update') THEN
    CREATE POLICY deliveries_company_update ON deliveries FOR UPDATE
    USING (
      id IN (
        SELECT db.delivery_id FROM delivery_bids db
        INNER JOIN companies c ON c.id = db.company_id
        WHERE c.auth_user_id = auth.uid() AND db.status = 'accepted'
      )
    );
  END IF;
END $$;
