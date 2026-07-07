-- Clean up debug introspection functions from this investigation.
DROP FUNCTION IF EXISTS public.debug_check_deliveries_triggers();
DROP FUNCTION IF EXISTS public.debug_check_function_source(text);
DROP FUNCTION IF EXISTS public.debug_search_function_refs(text);
DROP FUNCTION IF EXISTS public.debug_find_trigger_by_function(text);
DROP FUNCTION IF EXISTS public.debug_get_function_body(text);

-- update_rider_rating() was a leftover trigger function from before this
-- session's ratings redesign. Its owning trigger was already auto-dropped
-- when the old delivery_ratings table was replaced (20260707250000), so it
-- was not actually firing — but its body still references the old
-- delivery_ratings.rider_rating column shape, which no longer exists.
-- Dead code; drop it so it can't be accidentally reattached later.
DROP FUNCTION IF EXISTS public.update_rider_rating();
