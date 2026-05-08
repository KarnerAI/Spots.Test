-- ============================================
-- Spot Images Storage Bucket Setup
-- ============================================
-- Run this script in Supabase Dashboard → Storage
-- This creates a public bucket for storing spot cover images
--
-- IMPORTANT: Run this in the Supabase Dashboard, not in the SQL Editor
-- Go to: Storage → Create a new bucket
-- Bucket name: spot-images
-- Public bucket: Yes (images are not sensitive)
-- File size limit: 5MB
-- Allowed MIME types: image/jpeg, image/png, image/webp
--
-- After creating the bucket manually, run the RLS policies below in SQL Editor

-- ============================================
-- Storage RLS Policies for spot-images Bucket
-- ============================================

-- Policy: Anyone can read/view images (public bucket)
CREATE POLICY "Public Access"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'spot-images');

-- Policy: Authenticated users can upload images
CREATE POLICY "Authenticated users can upload spot images"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'spot-images');

-- Policy: Authenticated users can update their own uploads (if needed)
CREATE POLICY "Authenticated users can update spot images"
ON storage.objects FOR UPDATE
TO authenticated
USING (bucket_id = 'spot-images');

-- Policy: Authenticated users can delete images (if needed for cleanup)
CREATE POLICY "Authenticated users can delete spot images"
ON storage.objects FOR DELETE
TO authenticated
USING (bucket_id = 'spot-images');

-- ============================================
-- Setup Complete
-- ============================================
-- 
-- File naming convention: {place_id}.jpg
-- Example: ChIJN1t_tDeuEmsRUsoyG83frY4.jpg
--
-- Full public URL format:
-- https://{project-ref}.supabase.co/storage/v1/object/public/spot-images/{place_id}.jpg
--
-- Next steps:
-- 1. Create the bucket manually in Supabase Dashboard → Storage
-- 2. Run the RLS policies above in SQL Editor
-- 3. Test upload from the app
