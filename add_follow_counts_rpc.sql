-- ============================================
-- Migration: get_follow_counts RPC
-- ============================================
-- FollowService.counts() previously fired two parallel SELECTs (one per
-- direction) that returned full follow rows just so Swift could call
-- .count on the result arrays. Two round-trips, plus N rows shipped per
-- side just to count them.
--
-- This RPC returns both counts in one round-trip via COUNT(*) against
-- the existing follows_follower_status_idx and follows_followee_status_idx
-- composite indexes. Each subquery is an index-only scan: O(log N) probe
-- + sequential range scan of matching index entries (no heap fetch
-- because all needed columns are in the index).
--
-- RLS: SECURITY INVOKER. The follows policy "Follows: read own edges"
-- only lets a user read edges where they are participants — but COUNT(*)
-- against a column that the viewer isn't a participant in would return 0
-- under that policy. Since this RPC counts edges where p_user_id is the
-- participant (regardless of who's calling), we need to bypass that RLS
-- restriction.
--
-- Two options:
--   1. SECURITY DEFINER (function runs as the table owner, ignoring RLS)
--   2. Loosen the RLS policy on follows to permit aggregate reads
--
-- Going with (1) — narrower change, RLS stays intact for direct table
-- access. The function only returns aggregate counts (not row contents),
-- so privacy isn't leaked. Followers/following counts are already
-- displayed publicly in profiles regardless of follow relationship —
-- this matches existing UI behavior.
--
-- Run in Supabase Dashboard → Database → SQL Editor. Idempotent.

CREATE OR REPLACE FUNCTION public.get_follow_counts(p_user_id UUID)
RETURNS TABLE (followers INTEGER, following INTEGER)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    (SELECT COUNT(*)::INTEGER
       FROM public.follows
       WHERE followee_id = p_user_id
         AND status = 'accepted')                AS followers,
    (SELECT COUNT(*)::INTEGER
       FROM public.follows
       WHERE follower_id = p_user_id
         AND status = 'accepted')                AS following;
$$;

COMMENT ON FUNCTION public.get_follow_counts IS
  'Returns (followers, following) accepted-edge counts for p_user_id in one round-trip. SECURITY DEFINER because the follows RLS policy restricts row reads to participants only — aggregate counts of accepted edges are public-facing data already shown in profile headers, so bypassing RLS for the count is safe.';

-- ============================================
-- Verification (run manually after applying):
-- ============================================
--   SELECT * FROM public.get_follow_counts(
--     (SELECT id FROM auth.users LIMIT 1)
--   );
--
-- Expected: one row with two INTEGER columns (followers, following).
-- For a brand-new user: (0, 0).
