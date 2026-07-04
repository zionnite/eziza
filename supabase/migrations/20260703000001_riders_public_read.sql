-- Allow any authenticated user to read rider profile rows.
-- Customers need this to look up the assigned rider's auth_user_id when
-- loading the delivery tracking map; without it the riders SELECT returns
-- zero rows (blocked by the existing riders_select_own policy that only
-- permits auth_user_id = auth.uid()), so rider location tracking never starts.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'riders' AND policyname = 'riders_select_authenticated'
  ) THEN
    CREATE POLICY riders_select_authenticated ON riders
      FOR SELECT TO authenticated USING (true);
  END IF;
END $$;
