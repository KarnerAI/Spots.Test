-- Update upsert_spot to accept photo params expected by the client
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
