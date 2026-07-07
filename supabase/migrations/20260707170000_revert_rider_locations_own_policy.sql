-- Revert 20260707150000_fix_rider_locations_write_rls.sql — it was based on
-- a wrong assumption (that rider_locations.rider_id = riders.id, matching
-- deliveries.rider_id's convention). It does not: rider_locations.rider_id
-- is auth.uid() by design, already correctly fixed on 2026-07-04
-- (20260704000004_fix_rider_locations_fk.sql, whose own comment confirms
-- this explicitly). Restore the original, correct policy.
DROP POLICY IF EXISTS rider_locations_own ON rider_locations;
CREATE POLICY rider_locations_own ON rider_locations FOR ALL USING (rider_id = auth.uid());
