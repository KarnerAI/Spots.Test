-- ============================================
-- Migration: exclude self + add username to get_following_feed savers
-- ============================================
-- Builds on update_get_following_feed_with_savers.sql:
--   * other_savers_count and other_savers now exclude the viewer
--     (auth.uid()) in addition to the actor — seeing yourself in your own
--     feed's social proof is noise, not validation.
--   * Each other_savers entry now includes the saver's username, so the
--     feed card can render "Spotted by <username>[ and N others]" without
--     a second round trip.

CREATE OR REPLACE FUNCTION public.get_following_feed(
  p_cursor TIMESTAMPTZ DEFAULT NULL,
  p_limit  INTEGER     DEFAULT 20
)
RETURNS TABLE (
  id          TEXT,
  actor_id    UUID,
  kind        TEXT,
  created_at  TIMESTAMPTZ,
  payload     JSONB
)
LANGUAGE sql
STABLE
SECURITY INVOKER
AS $$
  WITH followed AS (
    SELECT followee_id
    FROM public.follows
    WHERE follower_id = auth.uid()
      AND status = 'accepted'
  ),
  spot_saves AS (
    SELECT
      'save:'  || sli.id::TEXT             AS id,
      ul.user_id                            AS actor_id,
      'spot_save'::TEXT                     AS kind,
      sli.saved_at                          AS created_at,
      jsonb_build_object(
        'list_id',            ul.id,
        'list_type',          ul.list_type,
        'list_name',          ul.name,
        'spot_id',            sli.spot_id,
        'other_savers_count', COALESCE(savers.cnt, 0),
        'other_savers',       COALESCE(savers.top3, '[]'::jsonb)
      )                                     AS payload
    FROM public.spot_list_items sli
    JOIN public.user_lists ul ON ul.id = sli.list_id
    JOIN followed f ON f.followee_id = ul.user_id
    LEFT JOIN LATERAL (
      WITH distinct_savers AS (
        SELECT DISTINCT ON (ul2.user_id)
          ul2.user_id,
          sli2.saved_at
        FROM public.spot_list_items sli2
        JOIN public.user_lists ul2 ON ul2.id = sli2.list_id
        WHERE sli2.spot_id   = sli.spot_id
          AND sli2.is_public = TRUE
          AND ul2.user_id   <> ul.user_id
          AND ul2.user_id   <> auth.uid()
        ORDER BY ul2.user_id, sli2.saved_at DESC
      ),
      ranked AS (
        SELECT user_id, saved_at
        FROM distinct_savers
        ORDER BY saved_at DESC
      )
      SELECT
        (SELECT COUNT(*) FROM ranked) AS cnt,
        COALESCE(
          (
            SELECT jsonb_agg(jsonb_build_object(
              'user_id',    p.id,
              'username',   p.username,
              'avatar_url', p.avatar_url
            ))
            FROM (SELECT user_id FROM ranked LIMIT 3) top
            JOIN public.profiles p ON p.id = top.user_id
          ),
          '[]'::jsonb
        ) AS top3
    ) savers ON TRUE
    WHERE sli.is_public = TRUE
      AND (p_cursor IS NULL OR sli.saved_at < p_cursor)
  ),
  list_creations AS (
    SELECT
      'list:' || ul.id::TEXT                AS id,
      ul.user_id                            AS actor_id,
      'list_created'::TEXT                  AS kind,
      ul.created_at                         AS created_at,
      jsonb_build_object(
        'list_id',   ul.id,
        'list_name', ul.name
      )                                     AS payload
    FROM public.user_lists ul
    JOIN followed f ON f.followee_id = ul.user_id
    WHERE ul.list_type IS NULL
      AND (p_cursor IS NULL OR ul.created_at < p_cursor)
  )
  SELECT id, actor_id, kind, created_at, payload
  FROM (
    SELECT * FROM spot_saves
    UNION ALL
    SELECT * FROM list_creations
  ) merged
  ORDER BY created_at DESC
  LIMIT GREATEST(1, LEAST(p_limit, 100));
$$;

COMMENT ON FUNCTION public.get_following_feed IS
  'Following-only feed for the authenticated user. spot_save payload includes other_savers_count and other_savers (top 3 by recency, with username + avatar_url) for stacked-avatar UI. Excludes both the actor and the viewer from savers.';
