-- Add company_rider_invites to Realtime so the rider dashboard receives
-- live invite events without requiring an app restart.
ALTER TABLE company_rider_invites REPLICA IDENTITY FULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'company_rider_invites'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE company_rider_invites;
  END IF;
END $$;

-- DB trigger: fire notify-rider-invite edge function on every invite INSERT
CREATE OR REPLACE TRIGGER on_invite_insert_notify_rider
AFTER INSERT ON public.company_rider_invites
FOR EACH ROW
EXECUTE FUNCTION supabase_functions.http_request(
  'https://nvwpsccleewgirlwokys.supabase.co/functions/v1/notify-rider-invite',
  'POST',
  '{"Content-Type":"application/json","Authorization":"Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im52d3BzY2NsZWV3Z2lybHdva3lzIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc4MjgxOTAzMCwiZXhwIjoyMDk4Mzk1MDMwfQ.f-awVmJTz5WF31IB9qCROcqlKj51-4lkig7t1EY8dyM"}',
  '{}',
  '5000'
);
