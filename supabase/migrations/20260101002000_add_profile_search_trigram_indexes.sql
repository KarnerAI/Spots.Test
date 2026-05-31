-- ============================================
-- Migration: trigram indexes for user search
-- ============================================
-- ProfileService.searchUsers (Spots.Test/Services/ProfileService.swift:159) runs:
--   profiles WHERE username ILIKE '%query%'
--           OR first_name ILIKE '%query%'
--           OR last_name  ILIKE '%query%'
--
-- Existing profiles_username_idx is a B-tree — only helps prefix matches
-- (LIKE 'foo%'), not substring matches (LIKE '%foo%'). Every keystroke in
-- user search currently does a full sequential scan of the profiles table.
--
-- Fix: GIN indexes using the pg_trgm operator class. PostgreSQL can use
-- gin_trgm_ops to accelerate ILIKE / LIKE substring patterns.
--
-- Run in Supabase Dashboard → Database → SQL Editor.
-- Idempotent.

-- Step 1: Ensure the trigram extension is available.
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- Step 2: GIN trigram indexes on the three search columns.
CREATE INDEX IF NOT EXISTS profiles_username_trgm_idx
  ON public.profiles USING GIN (username gin_trgm_ops);

CREATE INDEX IF NOT EXISTS profiles_first_name_trgm_idx
  ON public.profiles USING GIN (first_name gin_trgm_ops);

CREATE INDEX IF NOT EXISTS profiles_last_name_trgm_idx
  ON public.profiles USING GIN (last_name gin_trgm_ops);

-- ============================================
-- Verification (run manually after applying):
-- ============================================
--   EXPLAIN ANALYZE
--   SELECT id, username, first_name, last_name
--   FROM profiles
--   WHERE username ILIKE '%john%'
--      OR first_name ILIKE '%john%'
--      OR last_name  ILIKE '%john%'
--   LIMIT 25;
--
-- Expected before: "Seq Scan on profiles" with Filter on all three columns.
-- Expected after:  "Bitmap Index Scan" using one or more of the trgm indexes,
--                  combined via "BitmapOr".
--
-- Latency reference (with ~10k profiles):
--   Before: 50-200ms depending on row count
--   After:  <5ms
