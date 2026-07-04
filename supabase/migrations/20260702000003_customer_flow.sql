-- Default tenant for direct customer orders (fixed UUID, used as constant in app)
INSERT INTO tenants (id, name, email, is_active)
VALUES ('00000000-0000-0000-0000-000000000001', 'Eziza Direct', 'direct@eziza.com', true)
ON CONFLICT (id) DO NOTHING;

-- Add customer_id to deliveries (nullable — B2B deliveries from tenants leave this null)
ALTER TABLE deliveries ADD COLUMN IF NOT EXISTS customer_id UUID REFERENCES auth.users(id);
CREATE INDEX IF NOT EXISTS deliveries_customer_idx ON deliveries (customer_id) WHERE customer_id IS NOT NULL;

-- ── RLS ────────────────────────────────────────────────────────────────────────

-- Extend deliveries SELECT to include customer access
DROP POLICY IF EXISTS deliveries_rider_select ON deliveries;
CREATE POLICY deliveries_rider_select ON deliveries FOR SELECT
USING (
  status = 'open'
  OR customer_id = auth.uid()
  OR rider_id IN (SELECT id FROM riders WHERE auth_user_id = auth.uid())
  OR id IN (
    SELECT db.delivery_id FROM delivery_bids db
    INNER JOIN companies c ON c.id = db.company_id
    WHERE c.auth_user_id = auth.uid()
  )
);

-- Customer can insert their own delivery requests
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='deliveries' AND policyname='deliveries_customer_insert') THEN
    CREATE POLICY deliveries_customer_insert ON deliveries FOR INSERT
    WITH CHECK (customer_id = auth.uid());
  END IF;
END $$;

-- Customer can update their own deliveries (confirm receipt, cancel)
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='deliveries' AND policyname='deliveries_customer_update') THEN
    CREATE POLICY deliveries_customer_update ON deliveries FOR UPDATE
    USING (customer_id = auth.uid());
  END IF;
END $$;

-- Customer can read bids on their own deliveries
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='delivery_bids' AND policyname='bids_customer_select') THEN
    CREATE POLICY bids_customer_select ON delivery_bids FOR SELECT
    USING (
      delivery_id IN (SELECT id FROM deliveries WHERE customer_id = auth.uid())
    );
  END IF;
  -- Customer can accept/reject bids on their deliveries
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='delivery_bids' AND policyname='bids_customer_update') THEN
    CREATE POLICY bids_customer_update ON delivery_bids FOR UPDATE
    USING (
      delivery_id IN (SELECT id FROM deliveries WHERE customer_id = auth.uid())
    );
  END IF;
END $$;

-- Authenticated users can read basic rider info (needed for bid display to customers)
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='riders' AND policyname='riders_authenticated_read') THEN
    CREATE POLICY riders_authenticated_read ON riders FOR SELECT
    TO authenticated USING (true);
  END IF;
END $$;

-- Authenticated users can read basic company info (needed for bid display to customers)
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='companies' AND policyname='companies_authenticated_read') THEN
    CREATE POLICY companies_authenticated_read ON companies FOR SELECT
    TO authenticated USING (true);
  END IF;
END $$;
