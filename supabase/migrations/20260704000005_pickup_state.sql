-- Adds pickup_state to deliveries so riders can be matched by coverage area
-- (state-based) in addition to GPS radius.
ALTER TABLE deliveries ADD COLUMN IF NOT EXISTS pickup_state TEXT;
