-- ============================================
-- Migration: extend upsert_spot with country + rating
-- ============================================
-- Adds p_country and p_rating params to the existing upsert_spot RPC. Uses
-- COALESCE so a caller that doesn't have one of the new fields (e.g. older
-- clients passing nulls) won't clobber existing good data. New rows get
-- whatever the caller provides.
--
-- We CANNOT use CREATE OR REPLACE alone because Postgres treats new optional
-- params as a different signature for overload resolution; PostgREST then
-- can't disambiguate at call time. So drop the old signature explicitly,
-- then create the new one. All call sites pass named params, so positional
-- ordering doesn't matter.

DROP FUNCTION IF EXISTS public.upsert_spot(
  TEXT,                  -- p_place_id
  TEXT,                  -- p_name
  TEXT,                  -- p_address
  DOUBLE PRECISION,      -- p_latitude
  DOUBLE PRECISION,      -- p_longitude
  TEXT[],                -- p_types
  TEXT,                  -- p_photo_url
  TEXT,                  -- p_photo_reference
  TEXT                   -- p_city
);

CREATE OR REPLACE FUNCTION public.upsert_spot(
  p_place_id        TEXT,
  p_name            TEXT,
  p_address         TEXT,
  p_latitude        DOUBLE PRECISION,
  p_longitude       DOUBLE PRECISION,
  p_types           TEXT[],
  p_photo_url       TEXT DEFAULT NULL,
  p_photo_reference TEXT DEFAULT NULL,
  p_city            TEXT DEFAULT NULL,
  p_country         TEXT DEFAULT NULL,
  p_rating          NUMERIC DEFAULT NULL
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
    city,
    country,
    latitude,
    longitude,
    types,
    photo_url,
    photo_reference,
    rating,
    created_at,
    updated_at
  )
  VALUES (
    p_place_id,
    p_name,
    p_address,
    p_city,
    p_country,
    p_latitude,
    p_longitude,
    p_types,
    p_photo_url,
    p_photo_reference,
    p_rating,
    NOW(),
    NOW()
  )
  ON CONFLICT (place_id) DO UPDATE
  SET
    name            = EXCLUDED.name,
    address         = EXCLUDED.address,
    city            = COALESCE(EXCLUDED.city,            public.spots.city),
    country         = COALESCE(EXCLUDED.country,         public.spots.country),
    latitude        = EXCLUDED.latitude,
    longitude       = EXCLUDED.longitude,
    types           = EXCLUDED.types,
    photo_url       = COALESCE(EXCLUDED.photo_url,       public.spots.photo_url),
    photo_reference = COALESCE(EXCLUDED.photo_reference, public.spots.photo_reference),
    rating          = COALESCE(EXCLUDED.rating,          public.spots.rating),
    updated_at      = NOW();

  RETURN p_place_id;
END;
$$;

COMMENT ON FUNCTION public.upsert_spot IS
  'Insert or update a spot. New params: country (ISO short name from Google Places), rating (Google Places 0.0-5.0). COALESCE on cache fields so partial callers do not clobber existing data.';
