-- ============================================
-- Migration: add rating to spots
-- ============================================
-- Stores the Google Places rating (0.0 - 5.0). Optional; populated lazily
-- from the iOS client whenever a feed card needs it and the column is null.

ALTER TABLE public.spots
  ADD COLUMN IF NOT EXISTS rating numeric;

COMMENT ON COLUMN public.spots.rating IS
  'Google Places rating (0.0-5.0). Cached client-side write; nullable for legacy rows.';
