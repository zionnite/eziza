-- Phase 3: wallet ledger. Mirrors ZeeFashion's wallet_transaction
-- credit/debit/refunded incremental-trigger pattern (see CLAUDE.md rule:
-- never call an increment/decrement RPC alongside a wallet_transactions
-- insert — the trigger below is the only thing that ever moves
-- customers.wallet_balance).
CREATE TABLE IF NOT EXISTS public.wallet_transactions (
  id          BIGSERIAL PRIMARY KEY,
  customer_id UUID NOT NULL REFERENCES public.customers(id),
  amount      NUMERIC NOT NULL,
  type        TEXT NOT NULL CHECK (type IN ('credit', 'debit', 'refunded')),
  description TEXT,
  reference   TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_wallet_transactions_customer ON public.wallet_transactions(customer_id);

-- Idempotency guard for the Paystack webhook — charge.success can be
-- retried by Paystack, and a duplicate credit must never happen.
CREATE UNIQUE INDEX idx_wallet_transactions_reference
  ON public.wallet_transactions(reference) WHERE reference IS NOT NULL;

ALTER TABLE public.wallet_transactions ENABLE ROW LEVEL SECURITY;

CREATE POLICY wallet_transactions_select_own ON public.wallet_transactions FOR SELECT
USING (customer_id = auth.uid());

-- No INSERT policy for anon — every row is written by a SECURITY DEFINER
-- RPC or the Paystack webhook (service role), never a raw client insert.

CREATE OR REPLACE FUNCTION public.credit_wallet_transaction()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.type IN ('credit', 'refunded') THEN
    UPDATE public.customers
    SET wallet_balance = COALESCE(wallet_balance, 0) + NEW.amount
    WHERE id = NEW.customer_id;
  ELSIF NEW.type = 'debit' THEN
    UPDATE public.customers
    SET wallet_balance = COALESCE(wallet_balance, 0) - NEW.amount
    WHERE id = NEW.customer_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_credit_wallet_transaction ON public.wallet_transactions;
CREATE TRIGGER trg_credit_wallet_transaction
  AFTER INSERT ON public.wallet_transactions
  FOR EACH ROW EXECUTE FUNCTION public.credit_wallet_transaction();
