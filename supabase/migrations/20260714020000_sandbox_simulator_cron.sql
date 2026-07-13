-- Ticks progress-sandbox-deliveries every 15s. Uses net.http_post directly
-- (pg_net), same mechanism already used by this project's existing DB
-- webhook triggers on deliveries/delivery_bids/rider_locations -- the
-- service-role key embedded below is the same one already visible in those
-- trigger definitions, not a new exposure.
CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;

SELECT cron.schedule(
  'progress-sandbox-deliveries-tick',
  '15 seconds',
  $$
  SELECT net.http_post(
    url := 'https://nvwpsccleewgirlwokys.supabase.co/functions/v1/progress-sandbox-deliveries',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im52d3BzY2NsZWV3Z2lybHdva3lzIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc4MjgxOTAzMCwiZXhwIjoyMDk4Mzk1MDMwfQ.f-awVmJTz5WF31IB9qCROcqlKj51-4lkig7t1EY8dyM'
    ),
    body := '{}'::jsonb
  );
  $$
);
