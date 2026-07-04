-- DB webhook: fire notify-bid-placed edge function on every new bid INSERT
-- Notifies the customer that a bid has been placed on their delivery.

CREATE OR REPLACE TRIGGER on_bid_insert_notify_customer
AFTER INSERT ON public.delivery_bids
FOR EACH ROW
EXECUTE FUNCTION supabase_functions.http_request(
  'https://nvwpsccleewgirlwokys.supabase.co/functions/v1/notify-bid-placed',
  'POST',
  '{"Content-Type":"application/json","Authorization":"Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im52d3BzY2NsZWV3Z2lybHdva3lzIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc4MjgxOTAzMCwiZXhwIjoyMDk4Mzk1MDMwfQ.f-awVmJTz5WF31IB9qCROcqlKj51-4lkig7t1EY8dyM"}',
  '{}',
  '5000'
);
