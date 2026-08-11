-- Auto-recharge fast-follow, scoped in PROGRESS.md 2026-08-11: lets a
-- high-volume tenant top up automatically instead of guessing a lump sum
-- to prepay, without falling back to invoicing (which would reopen the
-- exposure the tenant-wallet-debit fix just closed). Opt-in only, off by
-- default -- every tenant keeps today's manual top-up behaviour unless
-- they explicitly turn it on in their own eziza-partners dashboard.
ALTER TABLE public.tenants
  ADD COLUMN IF NOT EXISTS auto_recharge_enabled          BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS auto_recharge_threshold        NUMERIC,
  ADD COLUMN IF NOT EXISTS auto_recharge_amount           NUMERIC,
  ADD COLUMN IF NOT EXISTS paystack_authorization_code    TEXT,
  ADD COLUMN IF NOT EXISTS auto_recharge_last_triggered_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS auto_recharge_charges_today    INT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS auto_recharge_day              DATE;

-- Fires on any wallet_balance decrease that crosses below the tenant's own
-- threshold, with two safety guards against a bug/runaway loop repeatedly
-- charging a real card: a 2-minute cooldown (Paystack + the webhook need a
-- few seconds to land the credit back) and a hard cap of 5 attempts/day,
-- reset per calendar day. Only fires on a *decrease* (OLD > NEW), never on
-- the recharge's own credit landing -- otherwise a recharge amount too
-- small to clear the threshold in one shot would immediately re-trigger
-- itself the moment its own credit posts.
CREATE OR REPLACE FUNCTION public.auto_recharge_tenant_wallet()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_today         DATE := current_date;
  v_charges_today INT;
BEGIN
  IF NOT NEW.auto_recharge_enabled THEN RETURN NEW; END IF;
  IF NEW.paystack_authorization_code IS NULL THEN RETURN NEW; END IF;
  IF NEW.auto_recharge_threshold IS NULL OR NEW.auto_recharge_amount IS NULL THEN RETURN NEW; END IF;
  IF NEW.wallet_balance >= NEW.auto_recharge_threshold THEN RETURN NEW; END IF;
  IF NEW.wallet_balance >= OLD.wallet_balance THEN RETURN NEW; END IF;

  IF NEW.auto_recharge_last_triggered_at IS NOT NULL
     AND NEW.auto_recharge_last_triggered_at > now() - interval '2 minutes' THEN
    RETURN NEW;
  END IF;

  v_charges_today := CASE WHEN NEW.auto_recharge_day = v_today THEN NEW.auto_recharge_charges_today ELSE 0 END;
  IF v_charges_today >= 5 THEN RETURN NEW; END IF;

  UPDATE public.tenants SET
    auto_recharge_last_triggered_at = now(),
    auto_recharge_charges_today     = v_charges_today + 1,
    auto_recharge_day               = v_today
  WHERE id = NEW.id;

  -- Deliberately NOT embedding the raw service-role key in this migration
  -- file (unlike ZeeFashion's own trigger_new_order_notification(), which
  -- does exactly that -- a real, separate secret-exposure risk not worth
  -- repeating here just because it's precedent). Reads it from
  -- supabase_vault instead, stored once via vault.create_secret() outside
  -- of any committed migration (see PROGRESS.md for the exact command) --
  -- this function only ever references the secret by name.
  PERFORM net.http_post(
    url     := 'https://nvwpsccleewgirlwokys.supabase.co/functions/v1/tenant-auto-recharge',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer ' || (
        SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1
      )
    ),
    body    := jsonb_build_object('tenant_id', NEW.id::text)
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_auto_recharge_tenant_wallet ON public.tenants;
CREATE TRIGGER trg_auto_recharge_tenant_wallet
  AFTER UPDATE OF wallet_balance ON public.tenants
  FOR EACH ROW
  EXECUTE FUNCTION public.auto_recharge_tenant_wallet();
