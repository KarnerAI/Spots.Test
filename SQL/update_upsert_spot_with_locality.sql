-- ============================================
-- Migration: extend upsert_spot with locality
-- ============================================
-- Adds p_locality TEXT param to upsert_spot. Same overload-resolution
-- constraints as the country/rating migration: drop the old signature
-- explicitly, then recreate. All callers use named params so positional
-- ordering doesn't matter.
--
-- COALESCE on locality so a partial caller (older client, debug script)
-- can't clobber an already-good value with null.

DROP FUNCTION IF EXISTS public.upsert_spot(
  TEXT,                  -- p_place_id
  TEXT,                  -- p_name
  TEXT,                  -- p_address
  DOUBLE PRECISION,      -- p_latitude
  DOUBLE PRECISION,      -- p_longitude
  TEXT[],                -- p_types
  TEXT,                  -- p_photo_url
  TEXT,                  -- p_photo_reference
  TEXT,                  -- p_city
  TEXT,                  -- p_country
  NUMERIC                -- p_rating
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
  p_rating          NUMERIC DEFAULT NULL,
  p_locality        TEXT DEFAULT NULL
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
    locality,
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
    p_locality,
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
    locality        = COALESCE(EXCLUDED.locality,        public.spots.locality),
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
  'Insert or update a spot. p_locality = Google Places "locality" addressComponent (Paris, Rome). p_city = administrative_area_level_1 (misnamed historical column, retained for region grouping). COALESCE on cache fields so partial callers do not clobber existing data.';
