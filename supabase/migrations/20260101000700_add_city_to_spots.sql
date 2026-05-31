-- Add city column to spots table
ALTER TABLE public.spots ADD COLUMN IF NOT EXISTS city TEXT;

COMMENT ON COLUMN public.spots.city IS 'City/locality extracted from Google Places addressComponents at save time.';
