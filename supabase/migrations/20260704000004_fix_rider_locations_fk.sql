-- rider_locations.rider_id stores auth.users.id (the rider's auth UID),
-- but the FK was pointing to riders.id (a different UUID). Every upsert
-- from the rider app was failing silently with an FK violation, leaving
-- rider_locations permanently empty and breaking customer location tracking.
ALTER TABLE rider_locations DROP CONSTRAINT IF EXISTS rider_locations_rider_id_fkey;

-- riders_own_location was designed for a schema where rider_id = riders.id.
-- It never matches now that rider_id = auth.uid(), so it is dead code.
-- rider_locations_own (rider_id = auth.uid()) is the correct policy.
DROP POLICY IF EXISTS riders_own_location ON rider_locations;
