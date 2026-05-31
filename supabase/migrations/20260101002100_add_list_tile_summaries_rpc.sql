-- ============================================
-- Migration: get_list_tile_summaries RPC
-- ============================================
-- Replaces the per-list round-trip pattern in ProfileTileBuilder.buildTiles
-- (Spots.Test/Helpers/ProfileSupportTypes.swift) with a single RPC call.
--
-- Before: opening any user's profile fired ~8 sequential Supabase queries
-- (3 system lists × {get_list_spot_count RPC + spot_list_items SELECT +
-- spots SELECT} + 2 across-lists). All serialized inside a for-loop.
--
-- After: 1 RPC returns count + most_recent_spot_id per list. Swift caller
-- aggregates the "All Spots" tile in memory and does 1 batch spots SELECT
-- for the up-to-4 cover place_ids. Two round-trips total.
--
-- Runs as SECURITY INVOKER so existing RLS policies on user_lists and
-- spot_list_items handle visibility (private accounts, follower-gated rows).
-- If the viewer can't see the target's lists, the RPC returns 0 rows and
-- UserProfileView falls back to its private-profile gate.
--
-- Performance: the inner correlated subqueries hit the existing index
--   spot_list_items_list_saved_idx ON (list_id, saved_at DESC)
-- so each list is O(1) for both the count and the most-recent lookup.
--
-- Run in Supabase Dashboard → Database → SQL Editor. Idempotent.

CREATE OR REPLACE FUNCTION public.get_list_tile_summaries(p_list_ids UUID[])
RETURNS TABLE (
  list_id              UUID,
  spot_count           INTEGER,
  most_recent_spot_id  TEXT,
  most_recent_saved_at TIMESTAMPTZ
)
LANGUAGE sql
STABLE
SECURITY INVOKER
AS $$
  SELECT
    ul.id AS list_id,
    (SELECT COUNT(*)::INT
       FROM public.spot_list_items sli
       WHERE sli.list_id = ul.id)                     AS spot_count,
    (SELECT sli.spot_id
       FROM public.spot_list_items sli
       WHERE sli.list_id = ul.id
       ORDER BY sli.saved_at DESC
       LIMIT 1)                                       AS most_recent_spot_id,
    (SELECT sli.saved_at
       FROM public.spot_list_items sli
       WHERE sli.list_id = ul.id
       ORDER BY sli.saved_at DESC
       LIMIT 1)                                       AS most_recent_saved_at
  FROM unnest(p_list_ids) AS input_list_id
  JOIN public.user_lists ul ON ul.id = input_list_id;
$$;

COMMENT ON FUNCTION public.get_list_tile_summaries IS
  'Returns spot_count + most-recent-saved spot per list_id, in one round-trip. SECURITY INVOKER respects RLS on user_lists and spot_list_items, so private/follower-gated rows are filtered out automatically.';

-- ============================================
-- Verification (run manually after applying):
-- ============================================
--   -- Replace these UUIDs with three real list ids from your user_lists table.
--   EXPLAIN ANALYZE SELECT * FROM public.get_list_tile_summaries(
--     ARRAY[
--       '00000000-0000-0000-0000-000000000001'::uuid,
--       '00000000-0000-0000-0000-000000000002'::uuid,
--       '00000000-0000-0000-0000-000000000003'::uuid
--     ]
--   );
--
-- Expected: "Index Scan using spot_list_items_list_saved_idx" for both the
-- COUNT subquery and the LIMIT 1 subquery. No "Seq Scan on spot_list_items".
-- (Caveat: tiny tables will still show Seq Scan because Postgres picks the
-- cheaper plan for small data — same as the trgm caveat for profiles.)
