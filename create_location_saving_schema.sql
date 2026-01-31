-- ============================================
-- Location-Saving Feature Database Schema
-- ============================================
-- Run this script in Supabase Dashboard → Database → SQL Editor
-- Execute the entire script in order
--
-- This schema enables users to save Google Places to personal lists:
-- - 3 default lists: Starred, Favorites, Bucket List
-- - All lists are private by default
-- - Users can add the same spot to multiple lists
-- - Spots are ordered by when they were saved (most recent first)
--
-- DESIGN DECISIONS:
-- 1. Separate 'spots' table stores place data once (shared across users)
--    - Prevents duplicate storage
--    - Enables future social features ("who else saved this?")
--    - Uses Google Place ID as primary identifier
-- 2. 'user_lists' table stores user's lists (3 default + future custom)
--    - Default lists created automatically via trigger
--    - Identified by list_type enum
-- 3. 'spot_list_items' junction table links spots to lists
--    - Stores saved_at timestamp for ordering
--    - Unique constraint prevents duplicates
-- 4. Store basic place data (name, address, coordinates) for:
--    - Fast queries without API calls
--    - Offline support
--    - Better UX

-- ============================================
-- Step 1: Create Enum Type for List Types
-- ============================================
-- Enum identifies the 3 default system lists
CREATE TYPE public.list_type_enum AS ENUM (
  'starred',
  'favorites',
  'bucket_list'
);

COMMENT ON TYPE public.list_type_enum IS 'Identifies the 3 default system lists: Starred, Favorites, and Bucket List. NULL indicates a custom user-created list.';

-- ============================================
-- Step 2: Create Spots Table
-- ============================================
-- Central repository for Google Place data
-- Stores place information once, shared across all users
-- This design enables future features like "who else saved this spot?"
CREATE TABLE public.spots (
  place_id TEXT PRIMARY KEY,  -- Google Place ID (unique identifier from Google Places API)
  name TEXT NOT NULL,          -- Place name
  address TEXT,                -- Formatted address from Google
  latitude DOUBLE PRECISION,   -- Location latitude
  longitude DOUBLE PRECISION,  -- Location longitude
  types TEXT[],                -- Array of place types from Google (e.g., ['restaurant', 'food'])
  photo_url TEXT,              -- Supabase Storage public URL for cover image
  photo_reference TEXT,        -- Google Places photo reference (for refresh/backup)
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),  -- When first saved by any user
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()   -- Last update time (for refreshing stale data)
);

-- Index for location-based queries (future feature: nearby spots)
CREATE INDEX spots_location_idx ON public.spots USING GIST (
  point(longitude, latitude)
);

COMMENT ON TABLE public.spots IS 'Central repository for Google Place data. Stores place information once, shared across all users. Uses Google Place ID as primary key.';
COMMENT ON COLUMN public.spots.place_id IS 'Google Place ID - unique identifier from Google Places API';
COMMENT ON COLUMN public.spots.types IS 'Array of place types from Google Places API (e.g., ["restaurant", "food", "point_of_interest"])';
COMMENT ON COLUMN public.spots.photo_url IS 'Supabase Storage public URL for the spot cover image. Cached to reduce Google Places API costs.';
COMMENT ON COLUMN public.spots.photo_reference IS 'Original Google Places photo reference. Used as backup or for refreshing the cached image.';

-- ============================================
-- Step 3: Create User Lists Table
-- ============================================
-- Stores user's lists (3 default system lists + future custom lists)
-- Default lists are created automatically via trigger when user signs up
CREATE TABLE public.user_lists (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  list_type public.list_type_enum,  -- NULL for custom lists, enum value for system lists
  name TEXT,                         -- Display name (NULL for system lists, required for custom)
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  
  -- Constraints
  CONSTRAINT user_lists_name_or_type_check CHECK (
    name IS NOT NULL OR list_type IS NOT NULL
  ),
  -- Ensure each user has only one of each system list type
  CONSTRAINT user_lists_unique_system_list UNIQUE (user_id, list_type)
);

-- Index for fast user list queries
CREATE INDEX user_lists_user_id_idx ON public.user_lists(user_id);

-- Index for finding system lists quickly
CREATE INDEX user_lists_user_type_idx ON public.user_lists(user_id, list_type) 
WHERE list_type IS NOT NULL;

COMMENT ON TABLE public.user_lists IS 'Stores user''s lists. Each user has exactly 3 default lists (Starred, Favorites, Bucket List) created automatically, plus any custom lists they create.';
COMMENT ON COLUMN public.user_lists.list_type IS 'Identifies system lists (starred, favorites, bucket_list). NULL indicates a custom user-created list.';
COMMENT ON COLUMN public.user_lists.name IS 'Display name for the list. NULL for system lists (they use list_type for display), required for custom lists.';

-- ============================================
-- Step 4: Create Spot List Items Table
-- ============================================
-- Junction table linking spots to lists (many-to-many relationship)
-- Enables: same spot in multiple lists, ordering by saved_at
CREATE TABLE public.spot_list_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  spot_id TEXT NOT NULL REFERENCES public.spots(place_id) ON DELETE CASCADE,
  list_id UUID NOT NULL REFERENCES public.user_lists(id) ON DELETE CASCADE,
  saved_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),  -- When added to list (for ordering)
  
  -- Prevent duplicate entries (same spot in same list)
  CONSTRAINT spot_list_items_unique_spot_list UNIQUE (spot_id, list_id)
);

-- Index for fast "show spots in list" queries (ordered by recency)
CREATE INDEX spot_list_items_list_saved_idx ON public.spot_list_items(list_id, saved_at DESC);

-- Index for fast "which lists contain this spot" queries
CREATE INDEX spot_list_items_spot_id_idx ON public.spot_list_items(spot_id);

COMMENT ON TABLE public.spot_list_items IS 'Junction table linking spots to lists. Enables many-to-many relationship: same spot can be in multiple lists, lists can have multiple spots.';
COMMENT ON COLUMN public.spot_list_items.saved_at IS 'Timestamp when spot was added to list. Used for ordering (most recent first).';

-- ============================================
-- Step 5: Enable Row Level Security (RLS)
-- ============================================
ALTER TABLE public.spots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_lists ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.spot_list_items ENABLE ROW LEVEL SECURITY;

-- ============================================
-- Step 6: Create RLS Policies for Spots Table
-- ============================================
-- Spots are public read (anyone can read spot data)
-- Insert/Update handled via function (service role or authenticated users)

-- Policy: Anyone can read spots (public data)
CREATE POLICY "Anyone can read spots"
  ON public.spots
  FOR SELECT
  USING (true);

-- Policy: Authenticated users can insert spots (when saving a new place)
CREATE POLICY "Authenticated users can insert spots"
  ON public.spots
  FOR INSERT
  WITH CHECK (auth.role() = 'authenticated');

-- Policy: Authenticated users can update spots (for refreshing stale data)
CREATE POLICY "Authenticated users can update spots"
  ON public.spots
  FOR UPDATE
  USING (auth.role() = 'authenticated');

-- ============================================
-- Step 7: Create RLS Policies for User Lists Table
-- ============================================
-- Users can only see/modify their own lists

-- Policy: Users can view their own lists
CREATE POLICY "Users can view own lists"
  ON public.user_lists
  FOR SELECT
  USING (auth.uid() = user_id);

-- Policy: Users can create lists for themselves
CREATE POLICY "Users can create own lists"
  ON public.user_lists
  FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- Policy: Users can update their own lists
CREATE POLICY "Users can update own lists"
  ON public.user_lists
  FOR UPDATE
  USING (auth.uid() = user_id);

-- Policy: Users can delete their own custom lists (but not system lists)
-- System lists are protected by check constraint in function
CREATE POLICY "Users can delete own custom lists"
  ON public.user_lists
  FOR DELETE
  USING (auth.uid() = user_id AND list_type IS NULL);

-- ============================================
-- Step 8: Create RLS Policies for Spot List Items Table
-- ============================================
-- Users can only see/modify items in their own lists

-- Policy: Users can view items in their own lists
CREATE POLICY "Users can view own list items"
  ON public.spot_list_items
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.user_lists
      WHERE user_lists.id = spot_list_items.list_id
      AND user_lists.user_id = auth.uid()
    )
  );

-- Policy: Users can add items to their own lists
CREATE POLICY "Users can add items to own lists"
  ON public.spot_list_items
  FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.user_lists
      WHERE user_lists.id = spot_list_items.list_id
      AND user_lists.user_id = auth.uid()
    )
  );

-- Policy: Users can remove items from their own lists
CREATE POLICY "Users can remove items from own lists"
  ON public.spot_list_items
  FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM public.user_lists
      WHERE user_lists.id = spot_list_items.list_id
      AND user_lists.user_id = auth.uid()
    )
  );

-- ============================================
-- Step 9: Create Helper Functions
-- ============================================

-- Function: Create default lists for a new user
-- Called automatically when user signs up
CREATE OR REPLACE FUNCTION public.create_default_lists_for_user(p_user_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Insert the 3 default lists if they don't exist
  INSERT INTO public.user_lists (user_id, list_type, name)
  VALUES
    (p_user_id, 'starred', NULL),
    (p_user_id, 'favorites', NULL),
    (p_user_id, 'bucket_list', NULL)
  ON CONFLICT (user_id, list_type) DO NOTHING;
END;
$$;

COMMENT ON FUNCTION public.create_default_lists_for_user IS 'Creates the 3 default lists (Starred, Favorites, Bucket List) for a new user. Called automatically via trigger on user signup.';

-- Function: Get spot count for a list
-- Used for displaying "5 places" badges
CREATE OR REPLACE FUNCTION public.get_list_spot_count(list_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  count_result INTEGER;
BEGIN
  SELECT COUNT(*) INTO count_result
  FROM public.spot_list_items
  WHERE spot_list_items.list_id = get_list_spot_count.list_id;
  
  RETURN count_result;
END;
$$;

COMMENT ON FUNCTION public.get_list_spot_count IS 'Returns the count of spots in a given list. Used for displaying list badges (e.g., "5 places").';

-- Function: Upsert spot data
-- Handles race conditions when multiple users save the same spot simultaneously
-- Updates existing spot if place_id already exists
CREATE OR REPLACE FUNCTION public.upsert_spot(
  p_place_id TEXT,
  p_name TEXT,
  p_address TEXT,
  p_latitude DOUBLE PRECISION,
  p_longitude DOUBLE PRECISION,
  p_types TEXT[],
  p_photo_url TEXT DEFAULT NULL,
  p_photo_reference TEXT DEFAULT NULL
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO public.spots (
    place_id,
    name,
    address,
    latitude,
    longitude,
    types,
    photo_url,
    photo_reference,
    created_at,
    updated_at
  )
  VALUES (
    p_place_id,
    p_name,
    p_address,
    p_latitude,
    p_longitude,
    p_types,
    p_photo_url,
    p_photo_reference,
    NOW(),
    NOW()
  )
  ON CONFLICT (place_id) DO UPDATE
  SET
    name = EXCLUDED.name,
    address = EXCLUDED.address,
    latitude = EXCLUDED.latitude,
    longitude = EXCLUDED.longitude,
    types = EXCLUDED.types,
    photo_url = COALESCE(EXCLUDED.photo_url, public.spots.photo_url),
    photo_reference = COALESCE(EXCLUDED.photo_reference, public.spots.photo_reference),
    updated_at = NOW();
  
  RETURN p_place_id;
END;
$$;

COMMENT ON FUNCTION public.upsert_spot IS 'Inserts or updates spot data. Handles race conditions when multiple users save the same spot simultaneously. Updates existing spot if place_id already exists.';

-- ============================================
-- Step 10: Create Triggers
-- ============================================

-- Trigger: Auto-create default lists when user signs up
-- This runs after user creation (works alongside existing profile creation trigger)
CREATE OR REPLACE FUNCTION public.create_lists_for_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Create default lists for the new user
  PERFORM public.create_default_lists_for_user(NEW.id);
  
  RETURN NEW;
END;
$$;

-- Create trigger to auto-create lists when user signs up
-- This runs after the existing profile creation trigger
CREATE TRIGGER on_auth_user_created_create_lists
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.create_lists_for_new_user();

COMMENT ON FUNCTION public.create_lists_for_new_user IS 'Creates default lists for a new user. Runs after user creation, works alongside existing profile creation trigger.';

-- Function: Create lists for existing users (migration helper)
-- Run this for users who signed up before this migration
CREATE OR REPLACE FUNCTION public.create_lists_for_existing_users()
RETURNS TABLE(created_count INTEGER)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  user_record RECORD;
  lists_created INTEGER := 0;
BEGIN
  -- For each user who doesn't have all 3 default lists, create them
  FOR user_record IN 
    SELECT DISTINCT u.id
    FROM auth.users u
    WHERE NOT EXISTS (
      SELECT 1 FROM public.user_lists ul
      WHERE ul.user_id = u.id
      AND ul.list_type IN ('starred', 'favorites', 'bucket_list')
      GROUP BY ul.user_id
      HAVING COUNT(DISTINCT ul.list_type) = 3
    )
  LOOP
    PERFORM public.create_default_lists_for_user(user_record.id);
    lists_created := lists_created + 1;
  END LOOP;
  
  RETURN QUERY SELECT lists_created;
END;
$$;

COMMENT ON FUNCTION public.create_lists_for_existing_users IS 'Migration helper: Creates default lists for all existing users who don''t have them yet. Run this once after migration for users who signed up before this schema was created.';

-- Trigger: Update updated_at timestamp on spot updates
CREATE OR REPLACE FUNCTION public.update_spots_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

CREATE TRIGGER update_spots_updated_at_trigger
  BEFORE UPDATE ON public.spots
  FOR EACH ROW
  EXECUTE FUNCTION public.update_spots_updated_at();

COMMENT ON FUNCTION public.update_spots_updated_at IS 'Automatically updates the updated_at timestamp when a spot is updated.';

-- ============================================
-- Step 11: Example Queries
-- ============================================
-- These queries demonstrate how the UI will interact with the schema

-- Example 1: Save a spot to a list
-- First, upsert the spot (handles race conditions)
-- Then, insert into spot_list_items (will fail if already exists - that's OK)
/*
SELECT public.upsert_spot(
  'ChIJN1t_tDeuEmsRUsoyG83frY4',  -- Google Place ID
  'Sydney Opera House',
  'Bennelong Point, Sydney NSW 2000, Australia',
  -33.8567844,
  151.213108,
  ARRAY['tourist_attraction', 'point_of_interest', 'establishment']
);

-- Then add to a list (get list_id first)
INSERT INTO public.spot_list_items (spot_id, list_id)
VALUES (
  'ChIJN1t_tDeuEmsRUsoyG83frY4',
  (SELECT id FROM public.user_lists WHERE user_id = auth.uid() AND list_type = 'favorites' LIMIT 1)
)
ON CONFLICT (spot_id, list_id) DO NOTHING;  -- Prevents duplicate
*/

-- Example 2: Remove a spot from a list
/*
DELETE FROM public.spot_list_items
WHERE spot_id = 'ChIJN1t_tDeuEmsRUsoyG83frY4'
  AND list_id = (SELECT id FROM public.user_lists WHERE user_id = auth.uid() AND list_type = 'favorites' LIMIT 1);
*/

-- Example 3: Get all spots in a list (ordered by recency, most recent first)
/*
SELECT 
  s.place_id,
  s.name,
  s.address,
  s.latitude,
  s.longitude,
  s.types,
  sli.saved_at
FROM public.spot_list_items sli
JOIN public.spots s ON s.place_id = sli.spot_id
WHERE sli.list_id = (SELECT id FROM public.user_lists WHERE user_id = auth.uid() AND list_type = 'favorites' LIMIT 1)
ORDER BY sli.saved_at DESC;
*/

-- Example 4: Get spot counts per list for current user
/*
SELECT 
  ul.id,
  ul.list_type,
  ul.name,
  COALESCE(COUNT(sli.id), 0) as spot_count
FROM public.user_lists ul
LEFT JOIN public.spot_list_items sli ON sli.list_id = ul.id
WHERE ul.user_id = auth.uid()
GROUP BY ul.id, ul.list_type, ul.name
ORDER BY 
  CASE ul.list_type
    WHEN 'starred' THEN 1
    WHEN 'favorites' THEN 2
    WHEN 'bucket_list' THEN 3
    ELSE 4
  END,
  ul.created_at;
*/

-- Example 5: Check which lists contain a specific spot
/*
SELECT 
  ul.id,
  ul.list_type,
  ul.name,
  sli.saved_at
FROM public.spot_list_items sli
JOIN public.user_lists ul ON ul.id = sli.list_id
WHERE sli.spot_id = 'ChIJN1t_tDeuEmsRUsoyG83frY4'
  AND ul.user_id = auth.uid()
ORDER BY sli.saved_at DESC;
*/

-- Example 6: Update spot data (refresh from Google Places API)
/*
UPDATE public.spots
SET
  name = 'Updated Name',
  address = 'Updated Address',
  latitude = -33.8567844,
  longitude = 151.213108,
  types = ARRAY['restaurant', 'food', 'point_of_interest'],
  updated_at = NOW()
WHERE place_id = 'ChIJN1t_tDeuEmsRUsoyG83frY4';
*/

-- ============================================
-- Migration Complete
-- ============================================
-- The schema is now ready for use!
--
-- IMPORTANT: For existing users (who signed up before this migration),
-- run this command to create their default lists:
--
-- SELECT * FROM public.create_lists_for_existing_users();
--
-- This will create the 3 default lists for all existing users who don't have them.
-- New users will get their lists automatically via the trigger.
--
-- Next steps:
-- 1. Run the migration helper for existing users (see command above)
-- 2. Test the schema with the example queries above
-- 3. Integrate with your Swift app using Supabase Swift client
-- 4. Handle edge cases (network errors, race conditions, etc.)

