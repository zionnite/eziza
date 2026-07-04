-- DB webhook: fire notify-new-job edge function on every new delivery INSERT
-- Uses supabase_functions.http_request which is pre-installed on all Supabase projects.

CREATE OR REPLACE TRIGGER on_delivery_insert_notify_riders
AFTER INSERT ON public.deliveries
FOR EACH ROW
EXECUTE FUNCTION supabase_functions.http_request(
  'https://nvwpsccleewgirlwokys.supabase.co/functions/v1/notify-new-job',
  'POST',
  '{"Content-Type":"application/json","Authorization":"Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im52d3BzY2NsZWV3Z2lybHdva3lzIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc4MjgxOTAzMCwiZXhwIjoyMDk4Mzk1MDMwfQ.f-awVmJTz5WF31IB9qCROcqlKj51-4lkig7t1EY8dyM"}',
  '{}',
  '5000'
);
