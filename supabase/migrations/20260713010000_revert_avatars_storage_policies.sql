-- Reverting the Supabase Storage approach from a few minutes ago — Eziza
-- already has its own Bunny CDN zone (see lib/services/bunny_service.dart,
-- BUNNY_STORAGE_URL/BUNNY_STORAGE_PULL_ZONE, used for rider-docs/*), so
-- avatars follow that same established pattern instead. The bucket itself
-- is deleted separately via the Storage API.
DROP POLICY IF EXISTS avatars_upload_own ON storage.objects;
DROP POLICY IF EXISTS avatars_update_own ON storage.objects;
DROP POLICY IF EXISTS avatars_delete_own ON storage.objects;
