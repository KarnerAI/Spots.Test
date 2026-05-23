-- Adds a true `locality` column to spots (Paris, Rome, Tokyo).
--
-- Background: `spots.city` was historically populated from Google Places
-- `administrative_area_level_1` (state/region/province) to drive the Travel
-- Map's region grouping. The column was never renamed, so for international
-- spots it produced awkward UI labels ("Île-de-France" under Eiffel Tower).
-- This migration adds the proper locality column alongside the misnamed one.
-- A follow-up TODO covers renaming `city` -> `region` (DB-side only, no
-- behavior change). Until then, Swift reads via `Spot.displayCity` which
-- prefers `locality` and falls back to `city` for pre-backfill rows.
ALTER TABLE public.spots ADD COLUMN IF NOT EXISTS locality TEXT;

COMMENT ON COLUMN public.spots.locality IS
  'Google Places "locality" addressComponent (e.g. Paris, Rome, Tokyo). Authoritative for city-context display.';

COMMENT ON COLUMN public.spots.city IS
  'DEPRECATED NAME — actually stores administrative_area_level_1 (region/state/province). Retained for region-grouping fallback. Prefer reading via Swift `Spot.displayCity` which falls back to this column when `locality` is null. Slated for rename to `region`.';
