-- Phase 6: in-app support tickets, ported near-verbatim from ZeeFashion's
-- support_tickets/support_messages schema (zeefashion/supabase/migrations/
-- 20260621240000_support_tickets.sql + 20260621300000_support_messages_
-- image_url.sql), adapted for Eziza:
--   * user_id/sender_id reference auth.users directly -- Eziza has no
--     unified `profiles` table the way ZeeFashion does (riders/companies/
--     customers are separate tables), so "who this ticket belongs to" is
--     just the auth uid; admin resolves display identity by checking those
--     3 tables server-side (eziza-admin), not via a DB join here.
--   * category list swapped for logistics-appropriate values (no
--     orders/products in Eziza).
--   * image_url included from day one instead of as a follow-up migration.

CREATE TABLE IF NOT EXISTS public.support_tickets (
  id          BIGSERIAL PRIMARY KEY,
  user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  subject     TEXT NOT NULL,
  category    TEXT NOT NULL CHECK (category IN (
                'delivery_issue', 'payment_issue', 'refund_issue',
                'account_issue', 'rider_issue', 'technical_issue', 'other'
              )),
  status      TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'in_progress', 'resolved', 'closed')),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.support_messages (
  id           BIGSERIAL PRIMARY KEY,
  ticket_id    BIGINT NOT NULL REFERENCES public.support_tickets(id) ON DELETE CASCADE,
  sender_id    UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  sender_type  TEXT NOT NULL CHECK (sender_type IN ('user', 'admin')),
  message      TEXT NOT NULL,
  image_url    TEXT,
  is_read      BOOLEAN NOT NULL DEFAULT FALSE,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_support_tickets_user    ON public.support_tickets(user_id);
CREATE INDEX IF NOT EXISTS idx_support_tickets_status  ON public.support_tickets(status);
CREATE INDEX IF NOT EXISTS idx_support_messages_ticket ON public.support_messages(ticket_id);

-- Bumps the parent ticket's updated_at on every new message so the ticket
-- list can sort by "most recently active". SECURITY DEFINER because the
-- inserting user (rider/company/customer) has no UPDATE policy on
-- support_tickets -- same lesson learned earlier this session on
-- credit_delivery_earnings()/credit_rider_rating(): a plain invoker-rights
-- trigger would silently no-op the UPDATE under the caller's own RLS.
CREATE OR REPLACE FUNCTION public.touch_support_ticket()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  UPDATE support_tickets SET updated_at = now() WHERE id = NEW.ticket_id;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_touch_support_ticket ON public.support_messages;
CREATE TRIGGER trg_touch_support_ticket
  AFTER INSERT ON public.support_messages
  FOR EACH ROW EXECUTE FUNCTION public.touch_support_ticket();

-- ── RLS ──────────────────────────────────────────────────────────────────
ALTER TABLE public.support_tickets  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.support_messages ENABLE ROW LEVEL SECURITY;

-- Tickets: any authenticated user (rider/company/customer) sees and creates
-- only their own. No UPDATE policy for users -- status is admin-only, and
-- the admin panel uses the service-role key, which bypasses RLS entirely.
CREATE POLICY support_tickets_select_own ON public.support_tickets
  FOR SELECT TO authenticated USING (auth.uid() = user_id);

CREATE POLICY support_tickets_insert_own ON public.support_tickets
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);

-- Messages: user sees messages on their own tickets only.
CREATE POLICY support_messages_select_own ON public.support_messages
  FOR SELECT TO authenticated USING (
    EXISTS (
      SELECT 1 FROM public.support_tickets t
      WHERE t.id = support_messages.ticket_id AND t.user_id = auth.uid()
    )
  );

-- User can send messages on their own tickets only, as themselves.
CREATE POLICY support_messages_insert_own ON public.support_messages
  FOR INSERT TO authenticated WITH CHECK (
    auth.uid() = sender_id
    AND sender_type = 'user'
    AND EXISTS (
      SELECT 1 FROM public.support_tickets t
      WHERE t.id = ticket_id AND t.user_id = auth.uid()
    )
  );

-- Realtime, so the ticket thread page gets admin replies live.
ALTER TABLE public.support_messages REPLICA IDENTITY FULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'support_messages'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.support_messages;
  END IF;
END $$;
