-- ============================================
-- Create User Profiles Table and Sync with Auth
-- ============================================
-- Run this script in Supabase Dashboard → Database → SQL Editor
-- Execute each section in order

-- ============================================
-- Step 1: Create Profiles Table
-- ============================================
CREATE TABLE public.profiles (
  id UUID REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
  username TEXT UNIQUE NOT NULL,
  first_name TEXT,
  last_name TEXT,
  email TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create index on username for faster lookups
CREATE INDEX profiles_username_idx ON public.profiles(username);

-- Create index on email for faster lookups
CREATE INDEX profiles_email_idx ON public.profiles(email);

-- ============================================
-- Step 2: Enable Row Level Security (RLS)
-- ============================================
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- ============================================
-- Step 3: Create RLS Policies
-- ============================================
-- Policy: Users can view their own profile
CREATE POLICY "Users can view own profile"
  ON public.profiles
  FOR SELECT
  USING (auth.uid() = id);

-- Policy: Users can update their own profile
CREATE POLICY "Users can update own profile"
  ON public.profiles
  FOR UPDATE
  USING (auth.uid() = id);

-- Policy: Users can insert their own profile (for trigger)
CREATE POLICY "Users can insert own profile"
  ON public.profiles
  FOR INSERT
  WITH CHECK (auth.uid() = id);

-- ============================================
-- Step 4: Create Function to Handle New User Signup
-- ============================================
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, username, first_name, last_name, email)
  VALUES (
    NEW.id,
    NEW.raw_user_meta_data->>'username',
    NEW.raw_user_meta_data->>'first_name',
    NEW.raw_user_meta_data->>'last_name',
    NEW.email
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- Step 5: Create Trigger to Auto-Create Profile
-- ============================================
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

-- ============================================
-- Step 6: Migrate Existing User (Optional)
-- ============================================
-- If you already have a user, run this to migrate them:
-- Replace '21bd5e15-8aac-40b6-9a6b-8f1d577488d1' with your actual user ID
-- You can find the user ID in Authentication → Users

INSERT INTO public.profiles (id, username, first_name, last_name, email)
SELECT 
  id,
  raw_user_meta_data->>'username',
  raw_user_meta_data->>'first_name',
  raw_user_meta_data->>'last_name',
  email
FROM auth.users
WHERE id = '21bd5e15-8aac-40b6-9a6b-8f1d577488d1'  -- Replace with actual user ID
ON CONFLICT (id) DO NOTHING;

