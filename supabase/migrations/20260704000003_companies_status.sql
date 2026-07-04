-- companies table may have been created before the status column was added
-- (CREATE TABLE IF NOT EXISTS skips the column when table already exists).
ALTER TABLE companies ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'pending';
