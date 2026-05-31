-- ============================================
-- PR-B: refactor get_following_feed + v4 follower RLS on spot_list_items
-- ============================================
-- Replaces the get_following_feed last defined in
-- 20260101003300_update_get_following_feed_for_kind.sql with the v3 +
-- v4 model:
--   * Source rows from feed_activities (both kinds: spot_save, conversion)
--   * Stop reading spot_list_items.is_public anywhere — outer dedupe AND
--     the inner "savers" LATERAL — per D9 + §07.5.
--   * Per-viewer privacy CTE: filter each row's list_ids[] array by what
--     the viewer can see (visibility + follow status + list_editors
--     invitation). Suppress row entirely if filtered array is empty.
--   * Emit lists payload as a JSONB array [{id, kind, name}, ...] so the
--     Swift renderer can consolidate ("favorited and added to Mexico City").
--   * list_created arm preserved as-is (it didn't read is_public).
--
-- Also replaces the legacy "Spot list items: followers can read public
-- items" policy with a v4 follower-read policy that gates on list
-- visibility instead of the deprecated per-save is_public column.

-- ============================================
-- (1) v4 follower-read RLS on spot_list_items
-- ============================================
-- Old policy: is_public = TRUE AND viewer_can_see_user_activity(...)
-- New policy: list visibility IN ('followers', 'public') AND
--             viewer_can_see_user_activity(...)
-- viewer_can_see_user_activity already handles: self / non-private profile
-- / accepted follower. Combined with the visibility filter:
--   * private list: only owner + invitees see (existing owner/editor policy)
--   * followers list: + accepted followers
--   * public list: + accepted followers + non-private-profile strangers

DROP POLICY IF EXISTS "Spot list items: followers can read public items"
  ON public.spot_list_items;

CREATE POLICY "Spot list items: followers can read visible lists"
  ON public.spot_list_items
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.user_lists ul
      WHERE ul.id = spot_list_items.list_id
        AND ul.visibility IN ('followers', 'public')
        AND public.viewer_can_see_user_activity(auth.uid(), ul.user_id)
    )
  );

COMMENT ON POLICY "Spot list items: followers can read visible lists"
  ON public.spot_list_items IS
  'v4 follower-read policy (PR-B / §07.5). Stops reading the deprecated '
  'spot_list_items.is_public column (D9). Gates on list-level visibility '
  '+ profile-level privacy via viewer_can_see_user_activity.';

-- ============================================
-- (2) get_following_feed v3
-- ============================================
-- SECURITY INVOKER so the per-viewer CTE inherits the caller's auth.uid()
-- naturally. The feed_activities table's owner-only SELECT policy is
-- bypassed by the function reading via the SECURITY INVOKER context —
-- which means we must enforce visibility in-function. The CTE below does
-- exactly that: every (actor, list_id) pair is checked against the v4
-- visibility predicate before its row surfaces.

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
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_viewer UUID := auth.uid();
BEGIN
  RETURN QUERY
  WITH followed AS (
    SELECT followee_id
    FROM public.follows
    WHERE follower_id = v_viewer
      AND status = 'accepted'
  ),
  -- For every feed_activities row from a followed user (or self), compute
  -- the subset of list_ids the viewer can actually see under v4 rules.
  -- A list is visible to the viewer iff:
  --   * viewer is the owner, OR
  --   * viewer is in list_editors (orthogonal invitation), OR
  --   * visibility = 'followers' AND viewer is accepted follower of owner, OR
  --   * visibility = 'public' AND viewer_can_see_user_activity passes
  --     (handles stranger gating via profiles.is_private).
  activity_with_visible_lists AS (
    SELECT
      fa.id,
      fa.user_id    AS actor_id,
      fa.kind,
      fa.spot_id,
      fa.created_at,
      ARRAY(
        SELECT ul.id
        FROM public.user_lists ul
        WHERE ul.id = ANY(fa.list_ids)
          AND (
            ul.user_id = v_viewer
            OR EXISTS (
              SELECT 1 FROM public.list_editors le
              WHERE le.list_id = ul.id AND le.user_id = v_viewer
            )
            OR (
              ul.visibility = 'followers'
              AND EXISTS (
                SELECT 1 FROM public.follows f
                WHERE f.follower_id = v_viewer
                  AND f.followee_id = ul.user_id
                  AND f.status = 'accepted'
              )
            )
            OR (
              ul.visibility = 'public'
              AND public.viewer_can_see_user_activity(v_viewer, ul.user_id)
            )
          )
      ) AS visible_list_ids
    FROM public.feed_activities fa
    JOIN followed flw ON flw.followee_id = fa.user_id
    WHERE (p_cursor IS NULL OR fa.created_at < p_cursor)
  ),
  -- Suppress rows where no list in the activity is visible to the viewer
  -- (§07.5 — all-list_ids-invisible suppression).
  visible_activities AS (
    SELECT *
    FROM activity_with_visible_lists
    WHERE array_length(visible_list_ids, 1) > 0
  ),
  -- Hydrate the visible list_ids into {id, kind, name} for the Swift
  -- renderer. Preserves array order matching visible_list_ids.
  spot_activities AS (
    SELECT
      CASE va.kind
        WHEN 'spot_save'  THEN 'save:' || va.id::TEXT
        WHEN 'conversion' THEN 'conv:' || va.id::TEXT
        ELSE                   'fa:'   || va.id::TEXT
      END                                  AS id,
      va.actor_id                          AS actor_id,
      va.kind                              AS kind,
      va.created_at                        AS created_at,
      jsonb_build_object(
        'spot_id',            va.spot_id,
        'lists',              COALESCE(lists.arr, '[]'::jsonb),
        'other_savers_count', COALESCE(savers.cnt, 0),
        'other_savers',       COALESCE(savers.top3, '[]'::jsonb)
      )                                    AS payload
    FROM visible_activities va
    LEFT JOIN LATERAL (
      SELECT jsonb_agg(
               jsonb_build_object('id', ul.id, 'kind', ul.kind, 'name', ul.name)
               ORDER BY ord
             ) AS arr
      FROM unnest(va.visible_list_ids) WITH ORDINALITY AS t(list_id, ord)
      JOIN public.user_lists ul ON ul.id = t.list_id
    ) lists ON TRUE
    -- Savers LATERAL: every OTHER user who has the same spot in a list
    -- visible to the viewer. Stops reading is_public per D9 + §07.5.
    LEFT JOIN LATERAL (
      WITH distinct_savers AS (
        SELECT DISTINCT ON (ul2.user_id)
          ul2.user_id,
          sli2.saved_at
        FROM public.spot_list_items sli2
        JOIN public.user_lists ul2 ON ul2.id = sli2.list_id
        WHERE sli2.spot_id      = va.spot_id
          AND ul2.user_id      <> va.actor_id
          AND ul2.user_id      <> v_viewer
          AND ul2.visibility IN ('followers', 'public')
          AND public.viewer_can_see_user_activity(v_viewer, ul2.user_id)
        ORDER BY ul2.user_id, sli2.saved_at DESC
      ),
      ranked AS (
        SELECT user_id, saved_at FROM distinct_savers ORDER BY saved_at DESC
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
  ),
  -- list_created arm — preserved as-is from the prior version. Surfaces
  -- only custom lists, never default-kind seed lists.
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
      AND ul.visibility IN ('followers', 'public')
      AND (p_cursor IS NULL OR ul.created_at < p_cursor)
  )
  SELECT id, actor_id, kind, created_at, payload
  FROM (
    SELECT * FROM spot_activities
    UNION ALL
    SELECT * FROM list_creations
  ) merged
  ORDER BY created_at DESC
  LIMIT GREATEST(1, LEAST(p_limit, 100));
END;
$$;

COMMENT ON FUNCTION public.get_following_feed IS
  'v3 following feed (PR-B). Sources spot_save + conversion rows from '
  'feed_activities; emits a JSONB lists array for consolidated rendering '
  '("favorited and added to Mexico City"). Per-viewer privacy CTE filters '
  'list_ids against v4 visibility (private/followers/public) + list_editors '
  '+ profile-level is_private. Stops reading spot_list_items.is_public '
  'entirely (D9 + §07.5). list_created arm preserves prior behavior, with '
  'a visibility gate added so private custom lists no longer surface.';
