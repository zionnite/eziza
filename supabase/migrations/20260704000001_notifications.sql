-- Universal FCM token store keyed by auth.uid().
-- Riders save here AND to riders.fcm_token (kept for notify-new-job backward compat).
-- Companies and customers only use this table.

CREATE TABLE IF NOT EXISTS device_tokens (
  auth_user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  token        TEXT        NOT NULL,
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE device_tokens ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'device_tokens' AND policyname = 'device_tokens_own'
  ) THEN
    CREATE POLICY device_tokens_own ON device_tokens
      FOR ALL
      USING     (auth_user_id = auth.uid())
      WITH CHECK (auth_user_id = auth.uid());
  END IF;
END $$;
