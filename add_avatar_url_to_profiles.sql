-- ============================================
-- Add avatar_url to profiles table
-- ============================================
-- Run in Supabase Dashboard → Database → SQL Editor

-- Step 1: Add avatar_url column to profiles
ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS avatar_url TEXT;

COMMENT ON COLUMN public.profiles.avatar_url IS 'Public URL of the user profile photo stored in Supabase Storage (avatars bucket).';

-- Step 2: Create the avatars storage bucket
-- NOTE: Run this via the Supabase Dashboard → Storage → New bucket
-- Bucket name: avatars
-- Public: true
-- Or use the SQL below if your Supabase version supports it:
-- INSERT INTO storage.buckets (id, name, public) VALUES ('avatars', 'avatars', true) ON CONFLICT DO NOTHING;

-- Step 3: RLS policies for avatars bucket
-- Allow authenticated users to upload/update their own avatar
CREATE POLICY "Users can upload own avatar"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'avatars'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

CREATE POLICY "Users can update own avatar"
ON storage.objects
FOR UPDATE
TO authenticated
USING (
  bucket_id = 'avatars'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

-- Allow public read of all avatars
CREATE POLICY "Avatars are publicly readable"
ON storage.objects
FOR SELECT
TO public
USING (bucket_id = 'avatars');
