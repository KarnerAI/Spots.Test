-- ============================================
-- Social Schema: follows + privacy + feed RPC
-- ============================================
-- Run this script in Supabase Dashboard → Database → SQL Editor.
-- Idempotent where practical; safe to re-run during development.
--
-- Adds:
--   1. profiles.is_private              (account-level visibility)
--   2. spot_list_items.is_public        (per-save visibility, primary control)
--   3. follows table + follow_status enum
--   4. RLS policies extending visibility for spot_list_items / user_lists / profiles
--      so accepted followers can see another user's public activity.
--   5. get_following_feed(p_cursor, p_limit) RPC — query-on-read feed.

-- ============================================
-- Step 1: Privacy columns
-- ============================================
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS is_private BOOLEAN NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN public.profiles.is_private IS
  'When TRUE, follow attempts create a pending request the user must approve. When FALSE, follows are auto-accepted.';

ALTER TABLE public.spot_list_items
  ADD COLUMN IF NOT EXISTS is_public BOOLEAN NOT NULL DEFAULT TRUE;

COMMENT ON COLUMN public.spot_list_items.is_public IS
  'When TRUE, this saved spot can appear in followers'' feeds (subject to account-level privacy and follow status). Default TRUE — opt-out, not opt-in.';

-- ============================================
-- Step 2: follows table + status enum
-- ============================================
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'follow_status') THEN
    CREATE TYPE public.follow_status AS ENUM ('pending', 'accepted');
  END IF;
END$$;

CREATE TABLE IF NOT EXISTS public.follows (
  follower_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  followee_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  status      public.follow_status NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (follower_id, followee_id),
  CONSTRAINT follows_no_self_follow CHECK (follower_id <> followee_id)
);

CREATE INDEX IF NOT EXISTS follows_followee_status_idx
  ON public.follows (followee_id, status);
CREATE INDEX IF NOT EXISTS follows_follower_status_idx
  ON public.follows (follower_id, status);

COMMENT ON TABLE public.follows IS
  'Directed follow graph. status=accepted means the viewer can see the followee''s public activity. status=pending means the followee has a private account and must approve.';

-- ============================================
-- Step 3: Bump updated_at on follow status change
-- ============================================
CREATE OR REPLACE FUNCTION public.touch_follows_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS follows_touch_updated_at ON public.follows;
CREATE TRIGGER follows_touch_updated_at
  BEFORE UPDATE ON public.follows
  FOR EACH ROW
  EXECUTE FUNCTION public.touch_follows_updated_at();

-- ============================================
-- Step 4: RLS — follows
-- ============================================
ALTER TABLE public.follows ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Follows: read own edges" ON public.follows;
CREATE POLICY "Follows: read own edges"
  ON public.follows
  FOR SELECT
  USING (auth.uid() IN (follower_id, followee_id));

-- Insert: follower creates the edge. Status is set by client; trigger below
-- normalizes it based on followee privacy so clients can't bypass approval.
DROP POLICY IF EXISTS "Follows: follower creates edge" ON public.follows;
CREATE POLICY "Follows: follower creates edge"
  ON public.follows
  FOR INSERT
  WITH CHECK (auth.uid() = follower_id);

-- Update: only the followee can flip pending → accepted (i.e. accept a request).
DROP POLICY IF EXISTS "Follows: followee accepts request" ON public.follows;
CREATE POLICY "Follows: followee accepts request"
  ON public.follows
  FOR UPDATE
  USING (auth.uid() = followee_id);

-- Delete: either party can remove the edge (unfollow OR remove follower / reject request).
DROP POLICY IF EXISTS "Follows: either party deletes edge" ON public.follows;
CREATE POLICY "Follows: either party deletes edge"
  ON public.follows
  FOR DELETE
  USING (auth.uid() IN (follower_id, followee_id));

-- ============================================
-- Step 5: Normalize follow status server-side
-- ============================================
-- Server decides 'accepted' vs 'pending' based on the followee's is_private flag.
-- Prevents a malicious client from inserting status='accepted' directly.
CREATE OR REPLACE FUNCTION public.normalize_follow_status()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  target_is_private BOOLEAN;
BEGIN
  SELECT is_private INTO target_is_private
  FROM public.profiles
  WHERE id = NEW.followee_id;

  IF COALESCE(target_is_private, FALSE) THEN
    NEW.status := 'pending';
  ELSE
    NEW.status := 'accepted';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS follows_normalize_status ON public.follows;
CREATE TRIGGER follows_normalize_status
  BEFORE INSERT ON public.follows
  FOR EACH ROW
  EXECUTE FUNCTION public.normalize_follow_status();

COMMENT ON FUNCTION public.normalize_follow_status IS
  'Forces follow.status to "accepted" for public targets and "pending" for private targets, regardless of what the client supplied.';

-- ============================================
-- Step 6: RLS — profiles (allow user search)
-- ============================================
-- Profiles need to be discoverable so users can search and follow each other.
-- We don't expose private fields; the existing schema is already non-sensitive
-- (id, username, names, avatar_url, cover_photo_url, is_private).
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Profiles: anyone can read" ON public.profiles;
CREATE POLICY "Profiles: anyone can read"
  ON public.profiles
  FOR SELECT
  USING (TRUE);

DROP POLICY IF EXISTS "Profiles: owner can insert" ON public.profiles;
CREATE POLICY "Profiles: owner can insert"
  ON public.profiles
  FOR INSERT
  WITH CHECK (auth.uid() = id);

DROP POLICY IF EXISTS "Profiles: owner can update" ON public.profiles;
CREATE POLICY "Profiles: owner can update"
  ON public.profiles
  FOR UPDATE
  USING (auth.uid() = id);

-- ============================================
-- Step 7: Helper — viewer_can_see_user_activity(viewer, target)
-- ============================================
-- Returns TRUE iff the viewer is allowed to see the target's public activity.
-- Used by RLS policies and by the feed RPC.
CREATE OR REPLACE FUNCTION public.viewer_can_see_user_activity(
  p_viewer UUID,
  p_target UUID
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
AS $$
  SELECT
    p_viewer = p_target
    OR (
      COALESCE((SELECT is_private FROM public.profiles WHERE id = p_target), FALSE) = FALSE
    )
    OR EXISTS (
      SELECT 1 FROM public.follows
      WHERE follower_id = p_viewer
        AND followee_id = p_target
        AND status = 'accepted'
    );
$$;

COMMENT ON FUNCTION public.viewer_can_see_user_activity IS
  'Visibility predicate: viewer is the target, OR target is public, OR viewer is an accepted follower of target.';

-- ============================================
-- Step 8: RLS — extend spot_list_items + user_lists for follower visibility
-- ============================================
-- Existing policies allow owners full access; add a viewer policy for followers.

DROP POLICY IF EXISTS "Spot list items: followers can read public items"
  ON public.spot_list_items;
CREATE POLICY "Spot list items: followers can read public items"
  ON public.spot_list_items
  FOR SELECT
  USING (
    is_public = TRUE
    AND EXISTS (
      SELECT 1
      FROM public.user_lists ul
      WHERE ul.id = spot_list_items.list_id
        AND public.viewer_can_see_user_activity(auth.uid(), ul.user_id)
    )
  );

-- Allow viewers to read another user's lists when visibility allows it.
-- Custom (user-named) lists are the only ones that surface as "list created" events.
DROP POLICY IF EXISTS "User lists: followers can read"
  ON public.user_lists;
CREATE POLICY "User lists: followers can read"
  ON public.user_lists
  FOR SELECT
  USING (
    public.viewer_can_see_user_activity(auth.uid(), user_id)
  );

-- spots table is already public-read; no change needed.

-- ============================================
-- Step 9: Feed RPC — get_following_feed
-- ============================================
-- Returns a chronological feed of activity from people the caller follows.
-- Two activity kinds:
--   'spot_save'    — payload: { list_id, list_type, list_name, spot_id }
--   'list_created' — payload: { list_id, list_name }
--
-- Cursor-based pagination: pass the created_at of the last item you saw
-- (or NULL for the first page). Returns rows strictly older than the cursor.
--
-- SECURITY INVOKER so existing RLS policies enforce visibility automatically.
CREATE OR REPLACE FUNCTION public.get_following_feed(
  p_cursor TIMESTAMPTZ DEFAULT NULL,
  p_limit  INTEGER     DEFAULT 20
)
RETURNS TABLE (
  id          TEXT,
  actor_id    UUID,
  kind        TEXT,
  created_at  TIMESTAMPTZ,
  payload     JSONB
)
LANGUAGE sql
STABLE
SECURITY INVOKER
AS $$
  WITH followed AS (
    SELECT followee_id
    FROM public.follows
    WHERE follower_id = auth.uid()
      AND status = 'accepted'
  ),
  spot_saves AS (
    SELECT
      'save:'  || sli.id::TEXT             AS id,
      ul.user_id                            AS actor_id,
      'spot_save'::TEXT                     AS kind,
      sli.saved_at                          AS created_at,
      jsonb_build_object(
        'list_id',   ul.id,
        'list_type', ul.list_type,
        'list_name', ul.name,
        'spot_id',   sli.spot_id
      )                                     AS payload
    FROM public.spot_list_items sli
    JOIN public.user_lists ul ON ul.id = sli.list_id
    JOIN followed f ON f.followee_id = ul.user_id
    WHERE sli.is_public = TRUE
      AND (p_cursor IS NULL OR sli.saved_at < p_cursor)
  ),
  list_creations AS (
    SELECT
      'list:' || ul.id::TEXT                AS id,
      ul.user_id                            AS actor_id,
      'list_created'::TEXT                  AS kind,
      ul.created_at                         AS created_at,
      jsonb_build_object(
        'list_id',   ul.id,
        'list_name', ul.name
      )                                     AS payload
    FROM public.user_lists ul
    JOIN followed f ON f.followee_id = ul.user_id
    WHERE ul.list_type IS NULL                -- custom lists only
      AND (p_cursor IS NULL OR ul.created_at < p_cursor)
  )
  SELECT id, actor_id, kind, created_at, payload
  FROM (
    SELECT * FROM spot_saves
    UNION ALL
    SELECT * FROM list_creations
  ) merged
  ORDER BY created_at DESC
  LIMIT GREATEST(1, LEAST(p_limit, 100));
$$;

COMMENT ON FUNCTION public.get_following_feed IS
  'Following-only feed for the authenticated user. Query-on-read across spot_list_items and user_lists. RLS handles visibility because this runs SECURITY INVOKER.';

-- ============================================
-- Step 10: Notes
-- ============================================
-- Phase 2 (likes / comments) will add tables keyed on (kind, ref_id) so the
-- RPC's stable id format ('save:<uuid>' / 'list:<uuid>') is the join key.
-- Phase 3 will add the UI to flip profiles.is_private and per-save is_public.
