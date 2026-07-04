-- Fix customer tracking map: "waiting for rider's location" never resolves.
--
-- Two root causes:
-- 1. rider_locations RLS only allows riders to read their own row (customers blocked)
-- 2. rider_locations not in supabase_realtime publication → no realtime events fired

-- REPLICA IDENTITY FULL so rider_id appears in UPDATE event payloads
ALTER TABLE rider_locations REPLICA IDENTITY FULL;

-- Allow all authenticated users to read any rider location row (needed by customers tracking live deliveries)
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'rider_locations' AND policyname = 'rider_locations_read_authenticated'
  ) THEN
    CREATE POLICY rider_locations_read_authenticated ON rider_locations
      FOR SELECT TO authenticated
      USING (true);
  END IF;
END $$;

-- Add to realtime publication
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'rider_locations'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE rider_locations;
  END IF;
END $$;
