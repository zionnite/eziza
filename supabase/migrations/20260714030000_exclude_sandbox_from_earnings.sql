-- Found live-verifying the sandbox simulator: credit_delivery_earnings()
-- doesn't know about is_sandbox, so a simulated delivery reaching
-- 'confirmed' created a real earnings_ledger row and credited a real
-- wallet_balance on the sandbox rider -- fake money mixed into real
-- reporting. Sandbox deliveries should never touch earnings at all.
CREATE OR REPLACE FUNCTION public.credit_delivery_earnings()
RETURNS TRIGGER AS $$
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
  IF NEW.is_sandbox THEN
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
$$ LANGUAGE plpgsql SECURITY DEFINER;
