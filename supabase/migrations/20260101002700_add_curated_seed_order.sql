-- ============================================
-- Curated Onboarding Seeds — spots.curated_seed_order
-- ============================================
-- Run this script in Supabase Dashboard → Database → SQL Editor.
-- Idempotent and reversible.
--
-- PURPOSE
-- Mark 12 specific rows in `public.spots` as the curated set surfaced
-- on the post-signup onboarding screens 2 (bucket list) and 3
-- (favorites). The iOS app queries:
--
--   SELECT * FROM spots
--   WHERE curated_seed_order IS NOT NULL
--   ORDER BY curated_seed_order;
--
-- and renders the rows in that order on both screens. The same 12
-- rows back both screens — screen 2 saves to bucket_list, screen 3
-- saves to starred. See post-signup onboarding plan for curation
-- rationale (Maya ICP: 4 NYC + 5 global icon + 2 nature + 1 Paris
-- food closer).
--
-- DATA SOURCE
-- The 12 rows were saved through the iOS app's PlacesAPIService on
-- 2026-05-11/12 so their name, address, lat/lng, types, photo_url,
-- photo_reference, city, country and rating are all populated by the
-- same production-tested code path the rest of the app uses. This
-- migration only sets the `curated_seed_order` column — it does NOT
-- insert spot rows.
--
-- ROTATION
-- To rotate the curated set later: SET curated_seed_order = NULL
-- for the spots being removed, set 1..N for the new spots. Update
-- `Spots.Test/Constants/CuratedSpots.swift` to match (it's
-- documentation, not source of truth).
--
-- DOWN MIGRATION
--   DROP INDEX IF EXISTS spots_curated_seed_idx;
--   ALTER TABLE public.spots DROP COLUMN IF EXISTS curated_seed_order;

-- ============================================
-- Step 1: Add the column
-- ============================================
ALTER TABLE public.spots
  ADD COLUMN IF NOT EXISTS curated_seed_order INT;

COMMENT ON COLUMN public.spots.curated_seed_order IS
  'NULL = ordinary spot. 1..N = position in the onboarding curated grid (screens 2 & 3). At most one row per position.';

-- ============================================
-- Step 2: Partial index for the onboarding query
-- ============================================
-- Most spots will have curated_seed_order = NULL; partial index
-- keeps the index tiny (only ~12 rows) and the lookup
-- ORDER BY curated_seed_order plan-optimal.
CREATE INDEX IF NOT EXISTS spots_curated_seed_idx
  ON public.spots (curated_seed_order)
  WHERE curated_seed_order IS NOT NULL;

-- ============================================
-- Step 3: Uniqueness — at most one spot per slot
-- ============================================
-- Prevents accidental dupes when rotating the curated set. NULLs
-- are allowed unlimited (default Postgres behavior on unique
-- indexes), so ordinary spots are unaffected.
CREATE UNIQUE INDEX IF NOT EXISTS spots_curated_seed_unique_idx
  ON public.spots (curated_seed_order)
  WHERE curated_seed_order IS NOT NULL;

-- ============================================
-- Step 4: Defensive reset before assigning
-- ============================================
-- If this migration is re-run after a rotation, clear any stale
-- ordering first so the UPDATEs below succeed against the unique
-- index. Safe no-op on first run.
UPDATE public.spots SET curated_seed_order = NULL WHERE curated_seed_order IS NOT NULL;

-- ============================================
-- Step 5: Assign positions 1..12
-- ============================================
-- Order matches Spots.Test/Constants/CuratedSpots.swift. Each
-- UPDATE asserts rows = 1 via the implicit "WHERE place_id = ..."
-- — if any place_id is missing from spots the statement is a
-- silent no-op. Run the verification block below to confirm all
-- 12 landed.

-- NYC local resonance (1-4)
UPDATE public.spots SET curated_seed_order = 1  WHERE place_id = 'ChIJ8Q2WSpJZwokRQz-bYYgEskM';  -- Joe's Pizza
UPDATE public.spots SET curated_seed_order = 2  WHERE place_id = 'ChIJCar0f49ZwokR6ozLV-dHNTE';  -- Katz's Delicatessen
UPDATE public.spots SET curated_seed_order = 3  WHERE place_id = 'ChIJK3vOQyNawokRXEa9errdJiU';  -- Brooklyn Bridge
UPDATE public.spots SET curated_seed_order = 4  WHERE place_id = 'ChIJmSvG_ZFZwokRTOFeiLXzkmA';  -- Carbone New York

-- Global iconic (5-9)
UPDATE public.spots SET curated_seed_order = 5  WHERE place_id = 'ChIJLU7jZClu5kcR4PcOOO6p3I0';  -- Eiffel Tower
UPDATE public.spots SET curated_seed_order = 6  WHERE place_id = 'ChIJrRMgU7ZhLxMRxAOFkC7I8Sg';  -- Colosseum
UPDATE public.spots SET curated_seed_order = 7  WHERE place_id = 'ChIJWZ2zdav40YURFvsU_rU3uaE';  -- Pujol
UPDATE public.spots SET curated_seed_order = 8  WHERE place_id = 'ChIJk_s92NyipBIRUMnDG8Kq2Js';  -- Basílica de la Sagrada Família
UPDATE public.spots SET curated_seed_order = 9  WHERE place_id = 'ChIJcWA7cPFuARURkSKaZwj5mxk';  -- Petra

-- Nature counter-balance (10-11)
UPDATE public.spots SET curated_seed_order = 10 WHERE place_id = 'ChIJe6hluYWP2oAR4p3rOqftdxk';  -- Joshua Tree National Park
UPDATE public.spots SET curated_seed_order = 11 WHERE place_id = 'ChIJsQi20Aldd1MRLrdJuq17Zx0';  -- Lake Louise

-- Paris pairing closer (12)
UPDATE public.spots SET curated_seed_order = 12 WHERE place_id = 'ChIJlz74sd5x5kcRJKnMHqMw2x8';  -- Le Comptoir du Relais

-- ============================================
-- Step 6: Verification (run interactively after migrating)
-- ============================================
-- Expect exactly 12 rows, ordered 1..12, all with non-null
-- photo_url. If any row is missing, re-save it through the app
-- and re-run the corresponding UPDATE above.
--
--   SELECT curated_seed_order,
--          name,
--          city,
--          photo_url IS NOT NULL AS has_photo
--     FROM public.spots
--    WHERE curated_seed_order IS NOT NULL
--    ORDER BY curated_seed_order;
--
-- Expected output:
--   1  Joe's Pizza                       New York       t
--   2  Katz's Delicatessen               New York       t
--   3  Brooklyn Bridge                   New York       t
--   4  Carbone New York                  New York       t
--   5  Eiffel Tower                      Île-de-France  t
--   6  Colosseum                         Lazio          t
--   7  Pujol                             Mexico City    t
--   8  Basílica de la Sagrada Família    Catalonia      t
--   9  Petra                             Ma'an Gov'rate t
--  10  Joshua Tree National Park         California     t
--  11  Lake Louise                       Alberta        t
--  12  Le comptoir du Relais             Île-de-France  t
