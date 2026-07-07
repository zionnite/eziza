-- Remove temporary diagnostic RPCs added during location-relay debugging.
DROP FUNCTION IF EXISTS public.debug_check_location_trigger();
DROP FUNCTION IF EXISTS public.debug_compare_location_trigger();
DROP FUNCTION IF EXISTS public.debug_recent_net_responses_v2(int);
DROP FUNCTION IF EXISTS public.debug_trigger_meta(text);
DROP FUNCTION IF EXISTS public.debug_trigger_meta_v2(text);
