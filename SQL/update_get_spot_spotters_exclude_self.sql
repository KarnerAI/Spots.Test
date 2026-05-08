-- ============================================
-- Migration: exclude self from get_spot_spotters
-- ============================================
-- Builds on get_spot_spotters.sql. The "Spotted By" sheet should surface
-- *other* people who saved the spot, not the viewer themselves. Filter
-- auth.uid() out of the distinct savers so the list and its count both
-- reflect the social-proof framing.

CREATE OR REPLACE FUNCTION public.get_spot_spotters(
  p_spot_id TEXT,
  p_limit   INTEGER DEFAULT 100,
  p_offset  INTEGER DEFAULT 0
)
RETURNS TABLE (
  user_id     UUID,
  username    TEXT,
  first_name  TEXT,
  last_name   TEXT,
  avatar_url  TEXT,
  saved_at    TIMESTAMPTZ
)
LANGUAGE sql
STABLE
SECURITY INVOKER
AS $$
  WITH distinct_savers AS (
    SELECT DISTINCT ON (ul.user_id)
      ul.user_id,
      sli.saved_at
    FROM public.spot_list_items sli
    JOIN public.user_lists ul ON ul.id = sli.list_id
    WHERE sli.spot_id   = p_spot_id
      AND sli.is_public = TRUE
      AND ul.user_id   <> auth.uid()
    ORDER BY ul.user_id, sli.saved_at DESC
  )
  SELECT
    p.id          AS user_id,
    p.username    AS username,
    p.first_name  AS first_name,
    p.last_name   AS last_name,
    p.avatar_url  AS avatar_url,
    s.saved_at    AS saved_at
  FROM distinct_savers s
  JOIN public.profiles p ON p.id = s.user_id
  ORDER BY s.saved_at DESC
  LIMIT  GREATEST(1, LEAST(p_limit, 500))
  OFFSET GREATEST(0, p_offset);
$$;

COMMENT ON FUNCTION public.get_spot_spotters IS
  'All users who have saved p_spot_id to a public list, most-recent first, excluding the viewer. Powers the Spotted By sheet.';
