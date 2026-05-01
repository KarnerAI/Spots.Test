-- ============================================
-- Migration: index for get_following_feed LATERAL
-- ============================================
-- Supports the "spotted by N others" subquery in get_following_feed:
--   WHERE sli2.spot_id = sli.spot_id AND sli2.is_public = TRUE
-- Partial index (is_public = TRUE) keeps the index narrow since private
-- saves are not eligible for the spotted-by aggregation anyway.

CREATE INDEX IF NOT EXISTS spot_list_items_spot_id_public_idx
  ON public.spot_list_items (spot_id)
  WHERE is_public = TRUE;
