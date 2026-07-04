-- Enable Supabase Realtime for the tables the app subscribes to.
-- REPLICA IDENTITY FULL ensures all column values appear in UPDATE events,
-- which is required for client-side filtering (e.g. checking customer_id or
-- delivery_id in the callback) to work reliably on row changes.

ALTER TABLE deliveries    REPLICA IDENTITY FULL;
ALTER TABLE delivery_bids REPLICA IDENTITY FULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'deliveries'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE deliveries;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'delivery_bids'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE delivery_bids;
  END IF;
END $$;
