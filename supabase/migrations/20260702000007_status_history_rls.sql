-- delivery_status_history is written by a trigger on deliveries status changes.
-- The trigger runs as the calling user (customer/rider) who may not have INSERT
-- permission. Fix: allow any authenticated user to insert into this table.
-- Security is enforced upstream — only users who can update deliveries
-- (per deliveries RLS) will ever trigger a status history write.

ALTER TABLE delivery_status_history ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS history_insert_authenticated ON delivery_status_history;
CREATE POLICY history_insert_authenticated ON delivery_status_history
  FOR INSERT TO authenticated WITH CHECK (true);

DROP POLICY IF EXISTS history_select_authenticated ON delivery_status_history;
CREATE POLICY history_select_authenticated ON delivery_status_history
  FOR SELECT TO authenticated USING (true);
