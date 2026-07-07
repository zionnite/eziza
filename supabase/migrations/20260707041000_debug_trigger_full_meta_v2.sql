-- Temporary diagnostic RPC — full trigger metadata (event/table/timing),
-- reading it straight out of pg_get_triggerdef's plain-English text instead
-- of decoding tgtype bit flags by hand (error-prone — got this wrong on the
-- first attempt). Excludes the Authorization header value. Drop after
-- debugging.
CREATE OR REPLACE FUNCTION public.debug_trigger_meta_v2(p_name text)
RETURNS TABLE (
  trigger_name text,
  table_name   text,
  enabled      text,
  event_clause text,
  url_in_def   text
)
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  def text;
BEGIN
  SELECT pg_get_triggerdef(t.oid) INTO def
  FROM pg_trigger t WHERE t.tgname = p_name;

  RETURN QUERY
  SELECT
    t.tgname::text,
    c.relname::text,
    t.tgenabled::text,
    (regexp_match(def, '(AFTER|BEFORE)\s+([A-Z\s]+?)\s+ON'))[1] || ' ' || (regexp_match(def, '(AFTER|BEFORE)\s+([A-Z\s]+?)\s+ON'))[2],
    (regexp_match(def, '(https://[^'']*)'))[1]
  FROM pg_trigger t
  JOIN pg_class c ON c.oid = t.tgrelid
  WHERE t.tgname = p_name;
END;
$$;

GRANT EXECUTE ON FUNCTION public.debug_trigger_meta_v2(text) TO service_role;
