-- OTP-based delivery confirmation.
-- Each delivery gets one active OTP row at a time. Previous rows are deleted
-- when a new OTP is requested (via the edge function), so this is a simple
-- lookup: find the latest non-expired, non-verified row for a delivery_id.

CREATE TABLE IF NOT EXISTS delivery_otps (
  id          bigserial   PRIMARY KEY,
  delivery_id uuid        NOT NULL REFERENCES deliveries(id) ON DELETE CASCADE,
  otp_hash    text        NOT NULL,          -- SHA-256 hex of the 6-digit code
  expires_at  timestamptz NOT NULL,
  attempts    int         NOT NULL DEFAULT 0, -- max 3 before rider must resend
  verified_at timestamptz,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS delivery_otps_delivery_idx ON delivery_otps (delivery_id);

-- All access is via the service-role edge function; no direct user access needed.
ALTER TABLE delivery_otps ENABLE ROW LEVEL SECURITY;
