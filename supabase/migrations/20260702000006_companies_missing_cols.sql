-- companies table was created with 'name' not 'company_name', and is missing
-- several columns that migrations assumed would be added via CREATE TABLE IF NOT EXISTS.
ALTER TABLE companies
  ADD COLUMN IF NOT EXISTS rating_avg     numeric  NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS rating_count   integer  NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS bank_name      text,
  ADD COLUMN IF NOT EXISTS account_number text,
  ADD COLUMN IF NOT EXISTS account_name   text,
  ADD COLUMN IF NOT EXISTS city           text;
