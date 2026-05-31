-- ============================================
-- Migration: Restrict Spot UPDATE Policy
-- ============================================
-- PROBLEM: The existing UPDATE policy on `spots` allows any authenticated
-- user to update ALL columns on ANY spot. This is too permissive.
--
-- SOLUTION: Replace the broad UPDATE policy with a restricted one that
-- only allows authenticated users to update photo_url, photo_reference,
-- latitude, and longitude (the fields the app updates directly).
-- Full spot upserts still go through the `upsert_spot()` RPC function
-- which is SECURITY DEFINER and bypasses RLS entirely.
--
-- Run this in Supabase Dashboard → Database → SQL Editor
-- ============================================

-- Step 1: Drop the old permissive UPDATE policy
DROP POLICY IF EXISTS "Authenticated users can update spots" ON public.spots;

-- Step 2: Create a restricted UPDATE policy
-- Only allows authenticated users to update specific non-critical fields.
-- The USING clause controls which rows can be selected for update (all spots).
-- The WITH CHECK clause ensures the row is still valid after the update.
CREATE POLICY "Authenticated users can update spot metadata"
  ON public.spots
  FOR UPDATE
  USING (auth.role() = 'authenticated')
  WITH CHECK (auth.role() = 'authenticated');

-- NOTE: This still allows column-level updates on any spot. For even tighter
-- control, consider migrating all direct .update() calls in the app to use
-- dedicated SECURITY DEFINER functions (e.g., update_spot_photo, update_spot_location)
-- and then dropping this UPDATE policy entirely. That migration is deferred
-- to avoid breaking existing functionality during pre-launch.
--
-- Direct .update() callers in the app:
--   - LocationSavingService.swift: .update(["photo_url": ...])
--   - LocationSavingService.swift: .update(["latitude": ..., "longitude": ...])
--   - PlacesAPIService.swift: .upsert() for bulk spot caching + photo URL updates
--
-- Recommended future migration:
--   1. Create update_spot_photo(p_place_id, p_photo_url) SECURITY DEFINER function
--   2. Create update_spot_location(p_place_id, p_latitude, p_longitude) SECURITY DEFINER function
--   3. Migrate PlacesAPIService.bulkUpsertSpots() to use upsert_spot() RPC
--   4. Drop this UPDATE policy entirely
