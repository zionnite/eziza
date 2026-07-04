-- Locations table: admin-managed state/city/area hierarchy
CREATE TABLE IF NOT EXISTS locations (
  id         SERIAL PRIMARY KEY,
  state      TEXT    NOT NULL,
  city       TEXT    NOT NULL,
  area       TEXT    NOT NULL,
  active     BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS locations_state_idx
  ON locations (state) WHERE active = true;

CREATE INDEX IF NOT EXISTS locations_state_city_idx
  ON locations (state, city) WHERE active = true;

-- Authenticated users can read active locations; admin web app uses service role
ALTER TABLE locations ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'locations' AND policyname = 'locations_authenticated_read'
  ) THEN
    CREATE POLICY locations_authenticated_read ON locations
      FOR SELECT TO authenticated
      USING (active = true);
  END IF;
END $$;

-- Add coverage_area_ids to companies (IDs from locations table)
ALTER TABLE companies ADD COLUMN IF NOT EXISTS coverage_area_ids INTEGER[] DEFAULT '{}';
