-- ============================================
-- Migration: get_most_explored_city RPC
-- ============================================
-- Replaces LocationSavingService.mostExploredCity(forLists:) which loaded
-- every saved spot id across every list (unbounded SELECT), then batch
-- fetched all unique spots' city + address, then counted in memory.
--
-- For a power user with N saved spots, that's O(N) rows over the wire
-- just to compute a single modal-city scalar. This RPC does the
-- aggregation server-side and returns one TEXT.
--
-- Behavior preserved:
--   * Counts each unique spot once even if saved across multiple lists
--     (matches Swift's Set<String> dedup pattern).
--   * Tie-breaker is alphabetical city name so result is deterministic.
--   * Returns NULL if the user has no saves with city populated. The Swift
--     caller falls back to the legacy address-parsing path in that case
--     (covers spots saved before the city column was backfilled).
--
-- RLS: SECURITY INVOKER. spot_list_items + user_lists policies handle
-- visibility. spots is public-read. If the viewer can't see the target's
-- saves, the RPC returns NULL.
--
-- Run in Supabase Dashboard → Database → SQL Editor. Idempotent.

CREATE OR REPLACE FUNCTION public.get_most_explored_city(p_user_id UUID)
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY INVOKER
AS $$
  SELECT s.city
  FROM public.spot_list_items sli
  JOIN public.user_lists       ul ON ul.id = sli.list_id
  JOIN public.spots            s  ON s.place_id = sli.spot_id
  WHERE ul.user_id = p_user_id
    AND s.city IS NOT NULL
    AND s.city <> ''
  GROUP BY s.city
  ORDER BY COUNT(DISTINCT sli.spot_id) DESC, s.city ASC
  LIMIT 1;
$$;

COMMENT ON FUNCTION public.get_most_explored_city IS
  'Returns the city in which p_user_id has saved the most distinct spots. NULL if the user has no saves with city populated. SECURITY INVOKER respects spot_list_items + user_lists RLS — followers/owner can compute, non-followers see NULL.';

-- ============================================
-- Verification (run manually after applying):
-- ============================================
--   SELECT public.get_most_explored_city(
--     (SELECT id FROM auth.users LIMIT 1)
--   );
--
-- Expected: a city name (e.g. "New York", "London") for any user that has
-- saved at least one spot with city populated, NULL otherwise.
