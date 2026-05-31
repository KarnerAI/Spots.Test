-- ============================================
-- Add cover_photo_url to profiles table
-- ============================================
-- Run in Supabase Dashboard → Database → SQL Editor

ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS cover_photo_url TEXT;

COMMENT ON COLUMN public.profiles.cover_photo_url IS
  'Unsplash URL of the user-selected cover photo. NULL = auto-select from most explored city.';
