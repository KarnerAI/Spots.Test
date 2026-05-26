-- ============================================
-- Migration: extend get_following_feed with a `visited` arm (T10)
-- ============================================
-- Phase B of T10 (decision T10-D2 from /plan-eng-review 2026-05-26).
--
-- Adds a new activity kind `visited` to the Following feed that fires the
-- first time a spot lands in a Favorites or Liked list for a given
-- (user, spot) pair — deduped per (user, spot) for life. This is the
-- "Maya visited Sagrada Família" Newsfeed card.
--
-- The visited activity is NOT sourced from `list_moves` — direct adds (a
-- save straight to Favorites with no prior Want-to-Go) must also surface
-- visited activities per T10-D2 (Maya's behavior per the strategy brief is
-- post-hoc collection, not pre-planning). The source is `spot_list_items`
-- filtered by list kind, with DISTINCT ON for the dedupe.
--
-- The `list_moves` event log is still maintained separately by the
-- `move_spot_between_lists` RPC for Phase 3 AI planner training — that's a
-- different signal from this feed-layer dedupe.
--
-- ---------- Collision with spot_save ----------
-- Without this migration, every favorites/liked add fires BOTH spot_save
-- and visited — two near-identical cards for the same event. To keep the
-- feed clean, this migration ALSO modifies the spot_save arm to exclude
-- favorites/liked kinds: spot_save now fires for want_to_go / custom /
-- trip / date_plan only. Visited owns the favorites/liked signal.
--
-- ---------- Privacy ----------
-- Both arms still require sli.is_public = TRUE, matching pre-T10
-- per-save visibility semantics.
--
-- Run order: apply AFTER update_get_following_feed_for_kind.sql.

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
    -- Saves to want_to_go / custom / trip / date_plan lists. Favorites and
    -- liked are handled by the `visited` arm below to avoid surfacing two
    -- cards for the same event.
    SELECT
      'save:'  || sli.id::TEXT             AS id,
      ul.user_id                            AS actor_id,
      'spot_save'::TEXT                     AS kind,
      sli.saved_at                          AS created_at,
      jsonb_build_object(
        'list_id',            ul.id,
        'list_kind',          ul.kind,
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
      AND ul.kind NOT IN ('favorites', 'liked')  -- T10: visited arm owns these
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
    WHERE ul.kind = 'custom'
      AND (p_cursor IS NULL OR ul.created_at < p_cursor)
  ),
  visited AS (
    -- T10: first-ever Favorites/Liked add per (user, spot). Deduped via
    -- DISTINCT ON keeping the earliest saved_at. The inner subquery does
    -- the dedupe; the outer applies followed-scope + cursor filter.
    --
    -- If the spot ends up in BOTH Favorites and Liked for the same user
    -- (no DB-level exclusivity per T10-D3), the earlier-saved row wins
    -- and `list_kind` / `list_name` carry that list's identity.
    SELECT
      'visited:' || v.user_id::TEXT || ':' || v.spot_id     AS id,
      v.user_id                                              AS actor_id,
      'visited'::TEXT                                        AS kind,
      v.first_visited_at                                     AS created_at,
      jsonb_build_object(
        'list_id',   v.list_id,
        'list_kind', v.list_kind,
        'list_name', v.list_name,
        'spot_id',   v.spot_id
      )                                                      AS payload
    FROM (
      SELECT DISTINCT ON (ul.user_id, sli.spot_id)
        ul.user_id,
        sli.spot_id,
        sli.list_id,
        ul.kind  AS list_kind,
        ul.name  AS list_name,
        sli.saved_at AS first_visited_at
      FROM public.spot_list_items sli
      JOIN public.user_lists ul ON ul.id = sli.list_id
      WHERE ul.kind IN ('favorites', 'liked')
        AND sli.is_public = TRUE
      ORDER BY ul.user_id, sli.spot_id, sli.saved_at ASC
    ) v
    JOIN followed f ON f.followee_id = v.user_id
    WHERE p_cursor IS NULL OR v.first_visited_at < p_cursor
  )
  SELECT id, actor_id, kind, created_at, payload
  FROM (
    SELECT * FROM spot_saves
    UNION ALL
    SELECT * FROM list_creations
    UNION ALL
    SELECT * FROM visited
  ) merged
  ORDER BY created_at DESC
  LIMIT GREATEST(1, LEAST(p_limit, 100));
$$;

COMMENT ON FUNCTION public.get_following_feed IS
  'Following-only feed. Three activity kinds: '
  'spot_save (saves to want_to_go / custom / trip / date_plan with '
  'other_savers carrying top 3 by recency); '
  'list_created (user-created custom lists); '
  'visited (T10: first-ever favorites/liked add per (user, spot), '
  'deduped lifetime). Excludes both actor and viewer from savers. '
  'Privacy via sli.is_public = TRUE.';
