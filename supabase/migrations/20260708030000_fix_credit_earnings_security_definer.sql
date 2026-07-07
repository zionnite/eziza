-- credit_delivery_earnings() writes to earnings_ledger (no INSERT policy exists —
-- it's meant to be a system-computed table, not user-writable) and to
-- riders/companies.wallet_balance. As a plain (SECURITY INVOKER) function, these
-- writes ran under the confirming user's own RLS grants and were silently
-- rejected, rolling back the whole `deliveries` status update. Real financial
-- bookkeeping triggered by a status transition should run as a system action,
-- not be gated by the confirming user's row-level permissions.
ALTER FUNCTION public.credit_delivery_earnings() SECURITY DEFINER SET search_path = public;
