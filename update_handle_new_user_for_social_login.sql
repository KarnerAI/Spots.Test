-- ============================================
-- Update handle_new_user() to support social logins (Google, Apple, etc.)
-- ============================================
-- Run in Supabase Dashboard → Database → SQL Editor
--
-- Problem: the original trigger expected `username`, `first_name`, `last_name`
-- in raw_user_meta_data (set by the email/password signup form). Social
-- providers supply different keys (`name`, `given_name`, `family_name`,
-- `picture`, `full_name`, `avatar_url`), so the INSERT failed on the
-- NOT NULL `username` column with "Database error saving new user".
--
-- This migration rewrites the trigger to:
--   1. Pull first_name / last_name from any of: first_name, given_name, name (split).
--   2. Pull avatar_url from avatar_url or picture.
--   3. Generate a unique username when none was supplied, derived from the
--      email local part (with a random suffix on collision).

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
  meta JSONB := COALESCE(NEW.raw_user_meta_data, '{}'::jsonb);
  resolved_username TEXT;
  resolved_first_name TEXT;
  resolved_last_name TEXT;
  resolved_avatar_url TEXT;
  base_username TEXT;
  suffix INT := 0;
BEGIN
  -- First / last name: prefer our keys, fall back to social provider keys.
  resolved_first_name := COALESCE(
    meta->>'first_name',
    meta->>'given_name',
    split_part(COALESCE(meta->>'full_name', meta->>'name', ''), ' ', 1)
  );
  resolved_last_name := COALESCE(
    meta->>'last_name',
    meta->>'family_name',
    NULLIF(
      regexp_replace(
        COALESCE(meta->>'full_name', meta->>'name', ''),
        '^\S+\s*', ''
      ),
      ''
    )
  );

  -- Avatar URL: our key OR Google's `picture`.
  resolved_avatar_url := COALESCE(meta->>'avatar_url', meta->>'picture');

  -- Username: use the supplied one if present, otherwise derive from email.
  resolved_username := NULLIF(meta->>'username', '');
  IF resolved_username IS NULL THEN
    base_username := lower(regexp_replace(split_part(NEW.email, '@', 1), '[^a-z0-9_]', '', 'g'));
    IF base_username IS NULL OR base_username = '' THEN
      base_username := 'user';
    END IF;
    resolved_username := base_username;
    -- Append a numeric suffix until we find a free username.
    WHILE EXISTS (SELECT 1 FROM public.profiles WHERE username = resolved_username) LOOP
      suffix := suffix + 1;
      resolved_username := base_username || suffix::text;
    END LOOP;
  END IF;

  INSERT INTO public.profiles (id, username, first_name, last_name, email, avatar_url)
  VALUES (
    NEW.id,
    resolved_username,
    resolved_first_name,
    resolved_last_name,
    NEW.email,
    resolved_avatar_url
  )
  ON CONFLICT (id) DO NOTHING;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- The trigger itself was already created by create_profiles_table.sql; this
-- only replaces the function body, so no DROP/CREATE TRIGGER is needed.
