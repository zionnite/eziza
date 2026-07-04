-- Add status field to riders (more granular than is_approved bool)
ALTER TABLE riders ADD COLUMN IF NOT EXISTS status text DEFAULT 'pending';
UPDATE riders SET status = 'approved' WHERE is_approved = true AND (status IS NULL OR status = 'pending');

-- Rider locations: create or normalise to latitude/longitude column names
CREATE TABLE IF NOT EXISTS rider_locations (
  rider_id   UUID PRIMARY KEY,
  latitude   DOUBLE PRECISION,
  longitude  DOUBLE PRECISION,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

DO $$ BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'rider_locations' AND column_name = 'lat'
  ) THEN
    ALTER TABLE rider_locations RENAME COLUMN lat TO latitude;
  END IF;
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'rider_locations' AND column_name = 'lng'
  ) THEN
    ALTER TABLE rider_locations RENAME COLUMN lng TO longitude;
  END IF;
END $$;

-- Companies table for logistics company registrations
CREATE TABLE IF NOT EXISTS companies (
  id             UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  auth_user_id   UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL UNIQUE,
  company_name   TEXT NOT NULL,
  cac_number     TEXT,
  contact_person TEXT NOT NULL,
  phone          TEXT NOT NULL,
  email          TEXT,
  coverage_states TEXT[] DEFAULT '{}',
  bank_name      TEXT,
  account_number TEXT,
  account_name   TEXT,
  bank_code      TEXT,
  status         TEXT DEFAULT 'pending',
  wallet_balance NUMERIC DEFAULT 0,
  total_earned   NUMERIC DEFAULT 0,
  paid_out       NUMERIC DEFAULT 0,
  rating_avg     NUMERIC DEFAULT 0,
  rating_count   INTEGER DEFAULT 0,
  created_at     TIMESTAMPTZ DEFAULT NOW()
);

-- Company rider invites (company sends invite to a rider by phone/email)
CREATE TABLE IF NOT EXISTS company_rider_invites (
  id            SERIAL PRIMARY KEY,
  company_id    UUID REFERENCES companies(id) ON DELETE CASCADE NOT NULL,
  rider_id      UUID REFERENCES auth.users(id),
  invited_phone TEXT,
  invited_email TEXT,
  status        TEXT DEFAULT 'pending',
  created_at    TIMESTAMPTZ DEFAULT NOW()
);

-- RLS: riders can read/write their own row
ALTER TABLE riders ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='riders' AND policyname='riders_select_own') THEN
    CREATE POLICY riders_select_own ON riders FOR SELECT USING (auth_user_id = auth.uid());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='riders' AND policyname='riders_insert_own') THEN
    CREATE POLICY riders_insert_own ON riders FOR INSERT WITH CHECK (auth_user_id = auth.uid());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='riders' AND policyname='riders_update_own') THEN
    CREATE POLICY riders_update_own ON riders FOR UPDATE USING (auth_user_id = auth.uid());
  END IF;
END $$;

-- RLS: companies can read/write their own row
ALTER TABLE companies ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='companies' AND policyname='companies_select_own') THEN
    CREATE POLICY companies_select_own ON companies FOR SELECT USING (auth_user_id = auth.uid());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='companies' AND policyname='companies_insert_own') THEN
    CREATE POLICY companies_insert_own ON companies FOR INSERT WITH CHECK (auth_user_id = auth.uid());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='companies' AND policyname='companies_update_own') THEN
    CREATE POLICY companies_update_own ON companies FOR UPDATE USING (auth_user_id = auth.uid());
  END IF;
END $$;

-- RLS: riders can read/write their own location
ALTER TABLE rider_locations ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='rider_locations' AND policyname='rider_locations_own') THEN
    CREATE POLICY rider_locations_own ON rider_locations FOR ALL USING (rider_id = auth.uid());
  END IF;
END $$;
