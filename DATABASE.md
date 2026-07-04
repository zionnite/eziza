# Eziza — Database Schema

Run this SQL in the new Supabase project (SQL Editor → New query).

## Step 1 — Core tables

```sql
-- Tenants (e-commerce platforms using the Eziza API)
CREATE TABLE tenants (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT NOT NULL,
  email       TEXT NOT NULL UNIQUE,
  webhook_url TEXT,
  is_active   BOOLEAN NOT NULL DEFAULT true,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- API Keys (hashed — plaintext never stored)
CREATE TABLE api_keys (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  key_hash    TEXT NOT NULL UNIQUE,
  label       TEXT,                  -- e.g. "ZeeFashion Production"
  last_used_at TIMESTAMPTZ,
  is_active   BOOLEAN NOT NULL DEFAULT true,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Riders
CREATE TABLE riders (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  auth_user_id    UUID UNIQUE REFERENCES auth.users(id) ON DELETE SET NULL,
  full_name       TEXT NOT NULL,
  phone           TEXT NOT NULL UNIQUE,
  email           TEXT,
  vehicle_type    TEXT NOT NULL CHECK (vehicle_type IN ('bike','car','van','truck')),
  vehicle_plate   TEXT,
  coverage_states TEXT[] NOT NULL DEFAULT '{}',
  bank_name       TEXT,
  account_number  TEXT,
  account_name    TEXT,
  is_approved     BOOLEAN NOT NULL DEFAULT false,
  is_available    BOOLEAN NOT NULL DEFAULT true,
  rating_avg      NUMERIC(3,2) NOT NULL DEFAULT 0,
  total_deliveries INT NOT NULL DEFAULT 0,
  wallet_balance  NUMERIC(12,2) NOT NULL DEFAULT 0,
  fcm_token       TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Logistics Companies
CREATE TABLE companies (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  auth_user_id UUID UNIQUE REFERENCES auth.users(id) ON DELETE SET NULL,
  name         TEXT NOT NULL,
  email        TEXT NOT NULL UNIQUE,
  phone        TEXT NOT NULL,
  state        TEXT NOT NULL,
  is_approved  BOOLEAN NOT NULL DEFAULT false,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Company ↔ Rider membership
CREATE TABLE company_riders (
  company_id  UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  rider_id    UUID NOT NULL REFERENCES riders(id) ON DELETE CASCADE,
  joined_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (company_id, rider_id)
);

-- Deliveries
CREATE TABLE deliveries (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id             UUID NOT NULL REFERENCES tenants(id),
  external_order_id     TEXT NOT NULL,        -- ZeeFashion order ID / any platform ID
  external_ref          TEXT,                 -- optional extra ref from tenant

  pickup_address        TEXT NOT NULL,
  pickup_lat            NUMERIC(10,7),
  pickup_lng            NUMERIC(10,7),
  pickup_contact_name   TEXT,
  pickup_contact_phone  TEXT,

  delivery_address      TEXT NOT NULL,
  delivery_lat          NUMERIC(10,7),
  delivery_lng          NUMERIC(10,7),
  delivery_contact_name  TEXT,
  delivery_contact_phone TEXT,

  package_description   TEXT,
  package_value         NUMERIC(12,2),

  status                TEXT NOT NULL DEFAULT 'open',
  -- open → assigned → awaiting_pickup_confirm → picked_up → delivered → confirmed | cancelled

  rider_id              UUID REFERENCES riders(id),
  agreed_price          NUMERIC(12,2),
  platform_fee          NUMERIC(12,2),        -- Eziza commission (agreed_price * fee_pct)

  bid_closes_at         TIMESTAMPTZ,
  assigned_at           TIMESTAMPTZ,
  picked_up_at          TIMESTAMPTZ,
  delivered_at          TIMESTAMPTZ,
  confirmed_at          TIMESTAMPTZ,
  cancelled_at          TIMESTAMPTZ,
  cancel_reason         TEXT,

  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX deliveries_tenant_external_idx
  ON deliveries (tenant_id, external_order_id);

-- Bids from riders on open deliveries
CREATE TABLE delivery_bids (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  delivery_id UUID NOT NULL REFERENCES deliveries(id) ON DELETE CASCADE,
  rider_id    UUID NOT NULL REFERENCES riders(id),
  amount      NUMERIC(12,2) NOT NULL,
  note        TEXT,
  status      TEXT NOT NULL DEFAULT 'pending',   -- pending | accepted | rejected
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (delivery_id, rider_id)
);

-- Status change audit trail
CREATE TABLE delivery_status_history (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  delivery_id UUID NOT NULL REFERENCES deliveries(id) ON DELETE CASCADE,
  status      TEXT NOT NULL,
  note        TEXT,
  actor_id    UUID,       -- rider_id or NULL (system)
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Real-time rider GPS (upserted by rider app)
CREATE TABLE rider_locations (
  rider_id   UUID PRIMARY KEY REFERENCES riders(id) ON DELETE CASCADE,
  lat        NUMERIC(10,7) NOT NULL,
  lng        NUMERIC(10,7) NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Ratings (after delivery confirmed)
CREATE TABLE delivery_ratings (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  delivery_id      UUID UNIQUE NOT NULL REFERENCES deliveries(id),
  rider_rating     INT CHECK (rider_rating BETWEEN 1 AND 5),
  customer_rating  INT CHECK (customer_rating BETWEEN 1 AND 5),
  rider_comment    TEXT,
  customer_comment TEXT,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Rider payout requests
CREATE TABLE rider_payout_requests (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  rider_id       UUID NOT NULL REFERENCES riders(id),
  amount         NUMERIC(12,2) NOT NULL,
  bank_name      TEXT,
  account_number TEXT,
  account_name   TEXT,
  status         TEXT NOT NULL DEFAULT 'pending',  -- pending | paid | rejected
  paid_at        TIMESTAMPTZ,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Webhook dispatch log (for debugging + retry)
CREATE TABLE webhook_dispatch_log (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  delivery_id     UUID REFERENCES deliveries(id),
  tenant_id       UUID NOT NULL REFERENCES tenants(id),
  event           TEXT NOT NULL,  -- delivery.assigned | delivery.picked_up | delivery.delivered | delivery.confirmed
  payload         JSONB NOT NULL,
  response_status INT,
  error           TEXT,
  dispatched_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Platform settings
CREATE TABLE settings (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

INSERT INTO settings (key, value) VALUES
  ('platform_fee_pct', '0.10'),     -- 10% Eziza commission on agreed price
  ('bid_window_minutes', '30');     -- bidding open for 30 min
```

## Step 2 — Triggers

```sql
-- Auto-update deliveries.updated_at
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$;

CREATE TRIGGER trg_deliveries_updated_at
  BEFORE UPDATE ON deliveries
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Log status changes automatically
CREATE OR REPLACE FUNCTION log_delivery_status()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.status <> OLD.status THEN
    INSERT INTO delivery_status_history (delivery_id, status, actor_id)
    VALUES (NEW.id, NEW.status, NEW.rider_id);
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_log_delivery_status
  AFTER UPDATE ON deliveries
  FOR EACH ROW EXECUTE FUNCTION log_delivery_status();

-- Update rider rating_avg after new rating
CREATE OR REPLACE FUNCTION update_rider_rating()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  UPDATE riders SET
    rating_avg = (
      SELECT ROUND(AVG(rider_rating)::NUMERIC, 2)
      FROM delivery_ratings dr
      JOIN deliveries d ON d.id = dr.delivery_id
      WHERE d.rider_id = (SELECT rider_id FROM deliveries WHERE id = NEW.delivery_id)
        AND dr.rider_rating IS NOT NULL
    ),
    total_deliveries = (
      SELECT COUNT(*) FROM deliveries
      WHERE rider_id = (SELECT rider_id FROM deliveries WHERE id = NEW.delivery_id)
        AND status = 'confirmed'
    )
  WHERE id = (SELECT rider_id FROM deliveries WHERE id = NEW.delivery_id);
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_update_rider_rating
  AFTER INSERT ON delivery_ratings
  FOR EACH ROW EXECUTE FUNCTION update_rider_rating();
```

## Step 3 — RLS Policies

```sql
ALTER TABLE riders ENABLE ROW LEVEL SECURITY;
ALTER TABLE deliveries ENABLE ROW LEVEL SECURITY;
ALTER TABLE delivery_bids ENABLE ROW LEVEL SECURITY;
ALTER TABLE rider_locations ENABLE ROW LEVEL SECURITY;
ALTER TABLE rider_payout_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE delivery_ratings ENABLE ROW LEVEL SECURITY;

-- Riders: read/update own profile
CREATE POLICY "riders_own" ON riders
  USING (auth_user_id = auth.uid())
  WITH CHECK (auth_user_id = auth.uid());

-- Deliveries: rider sees assigned + open deliveries
CREATE POLICY "riders_see_deliveries" ON deliveries
  FOR SELECT USING (
    status = 'open'
    OR rider_id = (SELECT id FROM riders WHERE auth_user_id = auth.uid())
  );

-- Bids: rider manages own bids, sees open delivery bids
CREATE POLICY "riders_bids" ON delivery_bids
  USING (rider_id = (SELECT id FROM riders WHERE auth_user_id = auth.uid()))
  WITH CHECK (rider_id = (SELECT id FROM riders WHERE auth_user_id = auth.uid()));

-- Rider location: upsert own location
CREATE POLICY "riders_own_location" ON rider_locations
  USING (rider_id = (SELECT id FROM riders WHERE auth_user_id = auth.uid()))
  WITH CHECK (rider_id = (SELECT id FROM riders WHERE auth_user_id = auth.uid()));

-- Payout requests: rider manages own
CREATE POLICY "riders_payouts" ON rider_payout_requests
  USING (rider_id = (SELECT id FROM riders WHERE auth_user_id = auth.uid()))
  WITH CHECK (rider_id = (SELECT id FROM riders WHERE auth_user_id = auth.uid()));

-- Ratings: rider can read own delivery ratings
CREATE POLICY "riders_ratings" ON delivery_ratings
  FOR SELECT USING (
    (SELECT rider_id FROM deliveries WHERE id = delivery_id)
    = (SELECT id FROM riders WHERE auth_user_id = auth.uid())
  );
```

## Step 4 — Realtime

```sql
-- Enable realtime on tables riders need live updates from
ALTER PUBLICATION supabase_realtime ADD TABLE deliveries;
ALTER PUBLICATION supabase_realtime ADD TABLE delivery_bids;
ALTER PUBLICATION supabase_realtime ADD TABLE rider_locations;
```

## Step 5 — First tenant (ZeeFashion)

```sql
-- Insert ZeeFashion as first tenant
INSERT INTO tenants (name, email, webhook_url)
VALUES (
  'ZeeFashion',
  'admin@zeefashion.space',
  'https://rtbmeqbryfwxtfvjwmfh.supabase.co/functions/v1/logistics-gateway'
);

-- Generate an API key — run this and save the output
-- Replace 'zeefashion-tenant-id' with the UUID returned above
SELECT
  t.id AS tenant_id,
  encode(gen_random_bytes(32), 'hex') AS raw_key,
  encode(digest(encode(gen_random_bytes(32), 'hex'), 'sha256'), 'hex') AS key_hash
FROM tenants t
WHERE t.name = 'ZeeFashion';

-- Then insert the key_hash into api_keys:
-- INSERT INTO api_keys (tenant_id, key_hash, label)
-- VALUES ('<tenant_id>', '<key_hash>', 'ZeeFashion Production');
-- Store the raw_key as EZIZA_API_KEY secret in ZeeFashion Supabase
```
