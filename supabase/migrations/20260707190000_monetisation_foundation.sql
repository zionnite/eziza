-- Monetisation foundation: commission deduction + earnings crediting.
--
-- Before this migration, riders.wallet_balance/companies.wallet_balance are
-- never written to anywhere in the codebase, and settings.platform_fee_pct /
-- deliveries.platform_fee exist but are never read or applied. This adds the
-- one authoritative place that both deducts commission and credits the
-- winning rider/company's balance when a delivery reaches 'confirmed' —
-- mirroring ZeeFashion's wallet_transaction -> update_wallet_balance()
-- incremental-trigger pattern (never update a balance column directly
-- alongside this, same rule as ZeeFashion's own CLAUDE.md).

ALTER TABLE public.deliveries
  ADD COLUMN IF NOT EXISTS delivery_fee_breakdown JSONB;

-- companies.wallet_balance/total_earned/paid_out don't actually exist —
-- company_dashboard_page.dart reads them from a raw Map with a `?? 0.0`
-- fallback, which was silently masking their absence (same class of bug as
-- riders.wallet_balance being a real-but-never-written column).
ALTER TABLE public.companies
  ADD COLUMN IF NOT EXISTS wallet_balance NUMERIC NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS total_earned   NUMERIC NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS paid_out       NUMERIC NOT NULL DEFAULT 0;

CREATE TABLE IF NOT EXISTS public.earnings_ledger (
  id                 BIGSERIAL PRIMARY KEY,
  delivery_id        UUID NOT NULL REFERENCES public.deliveries(id),
  rider_id           UUID REFERENCES public.riders(id),
  company_id         UUID REFERENCES public.companies(id),
  type               TEXT NOT NULL DEFAULT 'delivery_earning'
                       CHECK (type IN ('delivery_earning', 'adjustment')),
  gross_amount       NUMERIC NOT NULL,
  commission_amount  NUMERIC NOT NULL,
  net_amount         NUMERIC NOT NULL,
  created_at         TIMESTAMPTZ DEFAULT NOW(),
  CHECK ((rider_id IS NOT NULL) != (company_id IS NOT NULL))
);

CREATE INDEX IF NOT EXISTS idx_earnings_ledger_rider   ON public.earnings_ledger(rider_id);
CREATE INDEX IF NOT EXISTS idx_earnings_ledger_company ON public.earnings_ledger(company_id);
CREATE INDEX IF NOT EXISTS idx_earnings_ledger_delivery ON public.earnings_ledger(delivery_id);

ALTER TABLE public.earnings_ledger ENABLE ROW LEVEL SECURITY;

CREATE POLICY earnings_ledger_rider_select ON public.earnings_ledger FOR SELECT
USING (
  rider_id IN (SELECT id FROM public.riders WHERE auth_user_id = auth.uid())
);

CREATE POLICY earnings_ledger_company_select ON public.earnings_ledger FOR SELECT
USING (
  company_id IN (SELECT id FROM public.companies WHERE auth_user_id = auth.uid())
);

CREATE OR REPLACE FUNCTION public.credit_delivery_earnings()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  v_fee_pct    NUMERIC;
  v_gross      NUMERIC;
  v_commission NUMERIC;
  v_net        NUMERIC;
  v_company_id UUID;
BEGIN
  IF NEW.status != 'confirmed' OR OLD.status IS NOT DISTINCT FROM 'confirmed' THEN
    RETURN NEW;
  END IF;

  SELECT (value::NUMERIC) INTO v_fee_pct FROM public.settings WHERE key = 'platform_fee_pct';
  v_fee_pct := COALESCE(v_fee_pct, 0.10);

  v_gross := COALESCE(NEW.agreed_price, 0);
  v_commission := ROUND(v_gross * v_fee_pct, 2);
  v_net := v_gross - v_commission;

  -- Whoever's ACCEPTED bid won this delivery gets paid — a company-employed
  -- rider assigned internally does not get paid directly through the
  -- platform, the company does (same model as ZeeFashion's internal system).
  SELECT company_id INTO v_company_id
  FROM public.delivery_bids WHERE delivery_id = NEW.id AND status = 'accepted';

  UPDATE public.deliveries SET
    platform_fee = v_commission,
    delivery_fee_breakdown = jsonb_build_object(
      'gross_amount', v_gross, 'commission_pct', v_fee_pct,
      'commission_amount', v_commission, 'net_amount', v_net)
  WHERE id = NEW.id;

  INSERT INTO public.earnings_ledger (delivery_id, rider_id, company_id, gross_amount, commission_amount, net_amount)
  VALUES (NEW.id, CASE WHEN v_company_id IS NULL THEN NEW.rider_id END, v_company_id, v_gross, v_commission, v_net);

  IF v_company_id IS NOT NULL THEN
    UPDATE public.companies SET
      wallet_balance = COALESCE(wallet_balance, 0) + v_net,
      total_earned   = COALESCE(total_earned, 0) + v_net
    WHERE id = v_company_id;
  ELSE
    UPDATE public.riders SET wallet_balance = COALESCE(wallet_balance, 0) + v_net WHERE id = NEW.rider_id;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_credit_delivery_earnings ON public.deliveries;
CREATE TRIGGER trg_credit_delivery_earnings
  AFTER UPDATE ON public.deliveries
  FOR EACH ROW EXECUTE FUNCTION public.credit_delivery_earnings();

-- Backfill: credit any deliveries that were already 'confirmed' before this
-- trigger existed. A plain re-UPDATE won't fire the trigger (OLD.status is
-- already 'confirmed'), so run the same computation directly here, once,
-- for any confirmed delivery not yet in earnings_ledger.
DO $$
DECLARE
  v_fee_pct NUMERIC;
  d RECORD;
  v_gross NUMERIC;
  v_commission NUMERIC;
  v_net NUMERIC;
  v_company_id UUID;
BEGIN
  SELECT (value::NUMERIC) INTO v_fee_pct FROM public.settings WHERE key = 'platform_fee_pct';
  v_fee_pct := COALESCE(v_fee_pct, 0.10);

  FOR d IN
    SELECT * FROM public.deliveries
    WHERE status = 'confirmed'
      AND id NOT IN (SELECT delivery_id FROM public.earnings_ledger)
  LOOP
    v_gross := COALESCE(d.agreed_price, 0);
    v_commission := ROUND(v_gross * v_fee_pct, 2);
    v_net := v_gross - v_commission;

    SELECT company_id INTO v_company_id
    FROM public.delivery_bids WHERE delivery_id = d.id AND status = 'accepted';

    UPDATE public.deliveries SET
      platform_fee = v_commission,
      delivery_fee_breakdown = jsonb_build_object(
        'gross_amount', v_gross, 'commission_pct', v_fee_pct,
        'commission_amount', v_commission, 'net_amount', v_net)
    WHERE id = d.id;

    INSERT INTO public.earnings_ledger (delivery_id, rider_id, company_id, gross_amount, commission_amount, net_amount)
    VALUES (d.id, CASE WHEN v_company_id IS NULL THEN d.rider_id END, v_company_id, v_gross, v_commission, v_net);

    IF v_company_id IS NOT NULL THEN
      UPDATE public.companies SET
        wallet_balance = COALESCE(wallet_balance, 0) + v_net,
        total_earned   = COALESCE(total_earned, 0) + v_net
      WHERE id = v_company_id;
    ELSE
      UPDATE public.riders SET wallet_balance = COALESCE(wallet_balance, 0) + v_net WHERE id = d.rider_id;
    END IF;
  END LOOP;
END $$;
