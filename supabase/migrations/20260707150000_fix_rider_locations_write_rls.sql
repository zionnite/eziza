-- rider_locations.rider_id is populated with riders.id (the riders table's
-- own PK) everywhere in the app — but the existing rider_locations_own
-- policy checked `rider_id = auth.uid()`, comparing it against the
-- person's actual auth ID instead. Since riders.id is never equal to
-- riders.auth_user_id, every INSERT/UPDATE from the app's own authenticated
-- client (i.e. every real location push) has been silently rejected by RLS
-- this whole time, regardless of device — only service-role (RLS-bypassing)
-- writes ever succeeded. Fix: check via the riders table, matching the
-- established SECURITY DEFINER helper-function pattern already used
-- elsewhere in this schema (_auth_customer_delivery_ids, etc).

CREATE OR REPLACE FUNCTION _auth_rider_ids()
RETURNS SETOF uuid
LANGUAGE sql SECURITY DEFINER SET search_path = public
AS $$
  SELECT id FROM riders WHERE auth_user_id = auth.uid();
$$;

DROP POLICY IF EXISTS rider_locations_own ON rider_locations;
CREATE POLICY rider_locations_own ON rider_locations FOR ALL
USING (rider_id IN (SELECT _auth_rider_ids()))
WITH CHECK (rider_id IN (SELECT _auth_rider_ids()));
