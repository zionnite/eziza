-- Phase 3: customers currently have zero DB row — identity lives only in
-- auth.users.user_metadata. This table becomes the home for wallet_balance
-- (this migration) and later Phase 4's pin/pin_set + avatar.
CREATE TABLE IF NOT EXISTS public.customers (
  id             UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name      TEXT,
  phone          TEXT,
  avatar_url     TEXT,
  wallet_balance NUMERIC NOT NULL DEFAULT 0,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;

CREATE POLICY customers_select_own ON public.customers FOR SELECT
USING (id = auth.uid());

-- No UPDATE/INSERT policy for anon — wallet_balance must only ever move via
-- the wallet_transactions trigger (SECURITY DEFINER), never a direct write
-- from the customer's own session. Profile fields (full_name/phone/avatar)
-- get their own policy once Phase 5 (profile editing) lands.

-- Every auth user gets a customers row, regardless of whether they end up
-- registering as a rider/company too — anyone can be a sender.
CREATE OR REPLACE FUNCTION public.handle_new_customer()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.customers (id, full_name, phone)
  VALUES (
    NEW.id,
    NEW.raw_user_meta_data ->> 'full_name',
    NEW.raw_user_meta_data ->> 'phone'
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created_customer ON auth.users;
CREATE TRIGGER on_auth_user_created_customer
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_customer();

-- Backfill existing auth users.
INSERT INTO public.customers (id, full_name, phone)
SELECT u.id, u.raw_user_meta_data ->> 'full_name', u.raw_user_meta_data ->> 'phone'
FROM auth.users u
ON CONFLICT (id) DO NOTHING;
