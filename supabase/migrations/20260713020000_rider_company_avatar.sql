-- Phase 5: profile photo for riders/companies (customers already got
-- avatar_url in Phase 3). Uploaded via Eziza's own Bunny CDN zone, same as
-- rider-docs — this column just stores the resulting URL.
ALTER TABLE public.riders ADD COLUMN IF NOT EXISTS avatar_url TEXT;
ALTER TABLE public.companies ADD COLUMN IF NOT EXISTS avatar_url TEXT;

-- Extend the Phase 4 column-grant allowlists to cover it.
GRANT UPDATE (avatar_url) ON public.riders TO authenticated;

-- companies had zero self-update columns granted in Phase 4 (nothing used
-- it yet) — this is genuinely the first, so grant the full set of
-- Phase 5 profile-editable columns now rather than doing it column-by-column.
GRANT UPDATE (
  name, email, phone, state, city, contact_person, cac_number,
  bank_name, account_number, account_name, bank_code, avatar_url
) ON public.companies TO authenticated;
