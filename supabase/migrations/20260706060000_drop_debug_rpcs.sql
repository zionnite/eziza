-- Remove temporary diagnostic RPCs added during trigger-auth debugging.
DROP FUNCTION IF EXISTS public.debug_check_bid_triggers();
DROP FUNCTION IF EXISTS public.debug_recent_net_responses();
DROP FUNCTION IF EXISTS public.debug_compare_trigger_headers();
DROP FUNCTION IF EXISTS public.debug_diff_trigger_headers();
DROP FUNCTION IF EXISTS public.debug_recent_net_response_body(bigint);
