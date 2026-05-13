-- ============================================
-- Add onboarding_step to profiles + update handle_new_user trigger
-- ============================================
-- Run in Supabase Dashboard → Database → SQL Editor.
-- Idempotent and reversible.
--
-- PURPOSE
-- Backs the post-signup onboarding flow's resume-from-step semantics.
-- The iOS `AuthenticationViewModel` reads `profiles.onboarding_step`
-- after auth-state load and routes accordingly:
--
--   onboarding_step IS NULL  → user is "done" (or pre-dates this feature)
--                              → land on MainTabView
--   onboarding_step = 1..4   → resume the onboarding flow at that step
--
-- The integer tracks the FURTHEST step the user has reached (not the
-- literal current screen). Back-navigation does not decrement the
-- column (see plan Design D6).
--
-- The `handle_new_user` trigger is updated to set `onboarding_step = 1`
-- for every newly-created user. Existing users get NULL and bypass the
-- flow — they were onboarded under the old code path and shouldn't be
-- re-onboarded.
--
-- ROLLBACK
--   ALTER TABLE public.profiles DROP COLUMN IF EXISTS onboarding_step;
--   -- Then restore the prior handle_new_user definition from
--   -- create_profiles_table.sql (the version WITHOUT onboarding_step).

-- ============================================
-- Step 1: Add the column (NULL default = existing users bypass)
-- ============================================
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS onboarding_step SMALLINT;

COMMENT ON COLUMN public.profiles.onboarding_step IS
  'Post-signup onboarding state. NULL = completed/legacy user (skip onboarding). 1..4 = furthest step reached. Cleared to NULL on completion. Back-navigation does NOT decrement this column.';

-- Optional sanity check after running:
--   SELECT
--     COUNT(*) FILTER (WHERE onboarding_step IS NULL) AS legacy_users,
--     COUNT(*) FILTER (WHERE onboarding_step IS NOT NULL) AS in_flight_users
--   FROM public.profiles;
-- Expected immediately after migration: legacy_users = total, in_flight_users = 0.

-- ============================================
-- Step 2: Update handle_new_user to seed onboarding_step = 1
-- ============================================
-- CREATE OR REPLACE preserves the trigger binding on auth.users
-- without needing to drop/recreate it.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (
    id,
    username,
    first_name,
    last_name,
    email,
    onboarding_step
  )
  VALUES (
    NEW.id,
    NEW.raw_user_meta_data->>'username',
    NEW.raw_user_meta_data->>'first_name',
    NEW.raw_user_meta_data->>'last_name',
    NEW.email,
    1  -- New signups always start at step 1.
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- The CREATE TRIGGER on_auth_user_created statement from
-- create_profiles_table.sql is unchanged — we only rewrote the
-- function it executes.

-- ============================================
-- Step 3: Verification — trigger now seeds new rows correctly
-- ============================================
-- After deploying iOS, the next email/google signup should produce a
-- profiles row with onboarding_step = 1. To confirm:
--
--   SELECT id, username, onboarding_step, created_at
--     FROM public.profiles
--    ORDER BY created_at DESC
--    LIMIT 5;
-- Newest row should show onboarding_step = 1.
