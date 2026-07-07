-- DB webhook: fire dispatch-location-webhook edge function on every
-- rider_locations UPDATE. Relays the rider's live position to any tenant
-- whose delivery this rider is currently active on.
--
-- NOTE: replace <SERVICE_ROLE_JWT> below with the project's actual
-- service-role JWT before this trigger will actually authenticate (same
-- value used by the existing on_bid_insert_dispatch_tenant_webhook and
-- on_bid_insert_notify_customer triggers). Not hardcoded here deliberately
-- — avoid committing a live admin credential to git. Set the real value via
-- the Supabase Dashboard's Database → Webhooks UI after this migration runs.

CREATE OR REPLACE TRIGGER on_rider_location_dispatch_tenant_webhook
AFTER UPDATE ON public.rider_locations
FOR EACH ROW
EXECUTE FUNCTION supabase_functions.http_request(
  'https://nvwpsccleewgirlwokys.supabase.co/functions/v1/dispatch-location-webhook',
  'POST',
  '{"Content-Type":"application/json","Authorization":"Bearer <SERVICE_ROLE_JWT>"}',
  '{}',
  '5000'
);
