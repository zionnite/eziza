-- Push notification triggers for delivery status changes and bid acceptance.
-- Uses supabase_functions.http_request (pg_net-based) to call edge functions.
-- WHEN clauses prevent unnecessary function calls when status hasn't changed.

-- 1. Notify customer/rider on relevant delivery status changes
CREATE OR REPLACE TRIGGER on_delivery_update_notify
AFTER UPDATE ON public.deliveries
FOR EACH ROW
WHEN (OLD.status IS DISTINCT FROM NEW.status)
EXECUTE FUNCTION supabase_functions.http_request(
  'https://nvwpsccleewgirlwokys.supabase.co/functions/v1/notify-delivery-update',
  'POST',
  '{"Content-Type":"application/json","Authorization":"Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im52d3BzY2NsZWV3Z2lybHdva3lzIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc4MjgxOTAzMCwiZXhwIjoyMDk4Mzk1MDMwfQ.f-awVmJTz5WF31IB9qCROcqlKj51-4lkig7t1EY8dyM"}',
  '{}',
  '5000'
);

-- 2. Notify the winning rider/company when their bid is accepted
CREATE OR REPLACE TRIGGER on_bid_update_notify_accepted
AFTER UPDATE ON public.delivery_bids
FOR EACH ROW
WHEN (OLD.status IS DISTINCT FROM NEW.status AND NEW.status = 'accepted')
EXECUTE FUNCTION supabase_functions.http_request(
  'https://nvwpsccleewgirlwokys.supabase.co/functions/v1/notify-bid-accepted',
  'POST',
  '{"Content-Type":"application/json","Authorization":"Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im52d3BzY2NsZWV3Z2lybHdva3lzIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc4MjgxOTAzMCwiZXhwIjoyMDk4Mzk1MDMwfQ.f-awVmJTz5WF31IB9qCROcqlKj51-4lkig7t1EY8dyM"}',
  '{}',
  '5000'
);
