-- DB webhook: fire dispatch-bid-webhook edge function on every new bid INSERT.
-- Relays the bid to the owning tenant's webhook URL (e.g. ZeeFashion's
-- logistics-gateway) so tenant-created deliveries surface bids to their own
-- buyers. Additive alongside on_bid_insert_notify_customer, which continues
-- to push-notify self-service Eziza customers unchanged.
--
-- NOTE: replace <SERVICE_ROLE_JWT> below with the project's actual
-- service-role JWT before running this migration (same value used by the
-- existing on_bid_insert_notify_customer trigger in
-- 20260704000002_notify_bid_placed_webhook.sql). Not hardcoded here
-- deliberately — avoid committing a live admin credential to git.

CREATE OR REPLACE TRIGGER on_bid_insert_dispatch_tenant_webhook
AFTER INSERT ON public.delivery_bids
FOR EACH ROW
EXECUTE FUNCTION supabase_functions.http_request(
  'https://nvwpsccleewgirlwokys.supabase.co/functions/v1/dispatch-bid-webhook',
  'POST',
  '{"Content-Type":"application/json","Authorization":"Bearer <SERVICE_ROLE_JWT>"}',
  '{}',
  '5000'
);
