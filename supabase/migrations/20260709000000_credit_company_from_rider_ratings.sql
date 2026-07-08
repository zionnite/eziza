-- A rating on a company-employed rider reflects on the company too — a bad
-- rider rating is reputational risk for whoever employs them. Extend the
-- existing rider-rating trigger to also credit companies.rating_avg/count
-- when the rated rider has an accepted company_rider_invites row.
CREATE OR REPLACE FUNCTION public.credit_rider_rating()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_company_id UUID;
BEGIN
  IF NEW.ratee_role = 'rider' AND NEW.ratee_id IS NOT NULL THEN
    UPDATE public.riders SET
      rating_avg   = ((rating_avg * rating_count) + NEW.rating) / (rating_count + 1),
      rating_count = rating_count + 1
    WHERE id = NEW.ratee_id;

    SELECT cri.company_id INTO v_company_id
    FROM public.company_rider_invites cri
    JOIN public.riders r ON r.auth_user_id = cri.rider_id
    WHERE r.id = NEW.ratee_id AND cri.status = 'accepted'
    LIMIT 1;

    IF v_company_id IS NOT NULL THEN
      UPDATE public.companies SET
        rating_avg   = ((rating_avg * rating_count) + NEW.rating) / (rating_count + 1),
        rating_count = rating_count + 1
      WHERE id = v_company_id;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
