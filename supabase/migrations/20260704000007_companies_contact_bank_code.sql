-- Add columns missing from the initial companies schema
ALTER TABLE companies
  ADD COLUMN IF NOT EXISTS cac_number     text,
  ADD COLUMN IF NOT EXISTS contact_person text,
  ADD COLUMN IF NOT EXISTS bank_code      text;

-- Allow authenticated users to register their own company
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'companies'
      AND policyname = 'companies_insert_own'
  ) THEN
    CREATE POLICY companies_insert_own ON companies
      FOR INSERT TO authenticated
      WITH CHECK (auth.uid() = auth_user_id);
  END IF;
END $$;
