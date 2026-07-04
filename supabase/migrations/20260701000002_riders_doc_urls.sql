-- Store Bunny CDN URLs for rider KYC documents
alter table riders
  add column if not exists gov_id_url  text,
  add column if not exists selfie_url  text;
