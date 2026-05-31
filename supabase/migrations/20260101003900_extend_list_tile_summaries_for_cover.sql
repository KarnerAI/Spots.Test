-- ============================================
-- T21.2: Extend get_list_tile_summaries with effective_cover_*
-- ============================================
-- Per decision D-T21.1 + D-T21.4 in /plan-eng-review on 2026-05-25:
--
-- Auto-cover behavior: a list's effective cover is computed via
-- COALESCE(cover_image_url, most_recently_added_spot.photo_url). If
-- the user explicitly set cover_image_url (Settings → Change cover),
-- that wins. Otherwise the most-recently-added spot's photo becomes
-- the cover. If neither exists, both fields return NULL and the iOS
-- view falls back to cover_emoji.
--
-- The badge on List Detail header ("Cover from 'El Taquito'") needs
-- the spot's name + id, so the RPC returns them in the same payload.
-- This avoids a second round-trip (D-T21.4).
--
-- Change vs the original RPC (add_list_tile_summaries_rpc.sql, shipped
-- 2026-05-23): adds 3 new columns. DROP + CREATE because RETURNS TABLE
-- shape changed.
--
-- Performance: the new effective_cover_* fields reuse the same most-
-- recent-spot CTE pattern that already exists. One extra LEFT JOIN to
-- spots by place_id (PK lookup) per list. Profile carousel renders
-- 5-15 lists; per-list O(1). No N+1.

BEGIN;

DROP FUNCTION IF EXISTS public.get_list_tile_summaries(UUID[]);

CREATE OR REPLACE FUNCTION public.get_list_tile_summaries(p_list_ids UUID[])
RETURNS TABLE (
  list_id                          UUID,
  spot_count                       INTEGER,
  most_recent_spot_id              TEXT,
  most_recent_saved_at             TIMESTAMPTZ,
  effective_cover_url              TEXT,
  effective_cover_source_name      TEXT,
  effective_cover_source_spot_id   TEXT
)
LANGUAGE sql
STABLE
SECURITY INVOKER
AS $$
  WITH most_recent AS (
    SELECT
      sli.list_id,
      sli.spot_id,
      sli.saved_at,
      ROW_NUMBER() OVER (
        PARTITION BY sli.list_id ORDER BY sli.saved_at DESC
      ) AS rn
    FROM public.spot_list_items sli
    WHERE sli.list_id = ANY(p_list_ids)
  )
  SELECT
    ul.id AS list_id,
    (SELECT COUNT(*)::INT
       FROM public.spot_list_items sli
       WHERE sli.list_id = ul.id) AS spot_count,
    mr.spot_id AS most_recent_spot_id,
    mr.saved_at AS most_recent_saved_at,
    -- effective_cover_url: user-set cover wins; else most-recent spot's photo; else NULL
    COALESCE(ul.cover_image_url, s.photo_url) AS effective_cover_url,
    -- effective_cover_source_name: only populated when auto-derived from a spot
    CASE
      WHEN ul.cover_image_url IS NOT NULL THEN NULL
      WHEN s.photo_url IS NOT NULL THEN s.name
      ELSE NULL
    END AS effective_cover_source_name,
    -- effective_cover_source_spot_id: same condition as source_name
    CASE
      WHEN ul.cover_image_url IS NOT NULL THEN NULL
      WHEN s.photo_url IS NOT NULL THEN s.place_id
      ELSE NULL
    END AS effective_cover_source_spot_id
  FROM unnest(p_list_ids) AS input_list_id
  JOIN public.user_lists ul ON ul.id = input_list_id
  LEFT JOIN most_recent mr ON mr.list_id = ul.id AND mr.rn = 1
  LEFT JOIN public.spots s ON s.place_id = mr.spot_id;
$$;

COMMENT ON FUNCTION public.get_list_tile_summaries IS
  'Returns spot_count + most-recent-saved spot + effective cover '
  '(URL + source spot name + source spot id) per list_id, in one '
  'round-trip. Auto-cover: user-set cover_image_url wins; else the '
  'most-recently-added spot''s photo_url; else NULL (UI falls back '
  'to cover_emoji). SECURITY INVOKER respects RLS on user_lists, '
  'spot_list_items, and spots.';

COMMIT;

-- ============================================
-- Verification (run manually after applying):
-- ============================================
--   EXPLAIN ANALYZE SELECT * FROM public.get_list_tile_summaries(
--     ARRAY[
--       '00000000-0000-0000-0000-000000000001'::uuid,
--       '00000000-0000-0000-0000-000000000002'::uuid
--     ]
--   );
--
-- Expected:
--   - "Index Scan using spots_pkey" for the s.place_id lookup
--   - "Index Scan using spot_list_items_list_saved_idx" for the
--     ROW_NUMBER() window function
--   - No "Seq Scan on spots" or "Seq Scan on spot_list_items"
--
-- Sanity checks:
--   - List with no spots → effective_cover_url IS NULL, source fields NULL
--   - List w/ spots but most-recent has no photo → effective_cover_url IS NULL
--   - List w/ user-set cover_image_url → effective_cover_source_name IS NULL
--     (because the user picked it, not auto-derived)
--   - List w/ no cover_image_url + most-recent has photo → both source fields populated
