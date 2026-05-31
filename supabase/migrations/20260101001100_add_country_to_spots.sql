-- ============================================
-- Migration: add country to spots
-- ============================================
-- Stores the ISO short name (e.g. "USA", "JP") parsed from the Google Places
-- addressComponents. Optional; populated lazily from the iOS client whenever a
-- feed card or save flow has the data and the column is null.

ALTER TABLE public.spots
  ADD COLUMN IF NOT EXISTS country text;

COMMENT ON COLUMN public.spots.country IS
  'Country short name from Google Places addressComponents. Cached client-side write; nullable for legacy rows.';
