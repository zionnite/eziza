-- Add FCM device token to riders table for push notifications
alter table riders
  add column if not exists fcm_token text;
