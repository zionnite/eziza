-- Lets a sandbox tenant flag "I'm ready for live access" from their own
-- portal instead of emailing admin@eziza.online. Purely a visibility/queue
-- marker for eziza-admin -- promotion itself still goes through the
-- existing admin-only mode PATCH, unchanged.
ALTER TABLE public.tenants
  ADD COLUMN live_requested_at timestamptz;
