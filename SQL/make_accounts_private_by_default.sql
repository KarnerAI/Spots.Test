-- ============================================
-- Make all accounts private by default
-- ============================================
-- Flips the follow model from "auto-accept everything" to
-- "request-and-approve" by default.
--
-- 1. profiles.is_private DEFAULT changes FALSE -> TRUE
-- 2. All existing rows backfilled to is_private = TRUE
-- 3. follows table added to supabase_realtime publication so
--    iOS clients can subscribe to follower-count changes live
-- 4. handle_new_user() trigger explicitly sets is_private = TRUE
--    (defense in depth against a future migration that flips the
--    column default)
-- 5. New trigger auto_accept_pending_on_public_flip() resolves
--    any stranded pending requests when a user flips back to public
--
-- Existing accepted follow edges are preserved. The follows table
-- is NEVER touched by this migration.
--
-- Companion to create_social_schema.sql and add_onboarding_step_to_profiles.sql.

BEGIN;

-- 1. Column default flips to private going forward.
ALTER TABLE public.profiles
  ALTER COLUMN is_private SET DEFAULT TRUE;

-- 2. Backfill existing rows. Accepted follows in `follows` are NOT touched.
UPDATE public.profiles
  SET is_private = TRUE
  WHERE is_private = FALSE;

-- 3. Realtime publication: stream follows-table changes to clients so the
--    iOS app can react to inbound/outbound follow events live (used by
--    FollowService.observeFollowChanges). Without this, channel.subscribe()
--    succeeds but no events ever fire.
ALTER PUBLICATION supabase_realtime ADD TABLE public.follows;

-- 4. Defense in depth: signup trigger explicitly sets is_private = TRUE.
--    If a future migration flips the column DEFAULT, new signups stay
--    private. The rest of the body is preserved verbatim from
--    add_onboarding_step_to_profiles.sql (the existing source of truth
--    for this function).
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (
    id,
    username,
    first_name,
    last_name,
    email,
    onboarding_step,
    is_private
  )
  VALUES (
    NEW.id,
    COALESCE(
      NEW.raw_user_meta_data->>'username',
      'u_' || replace(NEW.id::text, '-', '')
    ),
    NEW.raw_user_meta_data->>'first_name',
    NEW.raw_user_meta_data->>'last_name',
    NEW.email,
    1,    -- New signups always start at step 1.
    TRUE  -- New signups are private by default.
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 5. When a user flips from private to public, auto-accept any stranded
--    pending requests. Symmetric with normalize_follow_status() — that one
--    fires on INSERT/UPDATE of `follows`; this one fires on UPDATE of
--    profiles.is_private. Without this, pending requests sent while the
--    user was private would sit forever even though the user no longer
--    requires approval.
CREATE OR REPLACE FUNCTION public.auto_accept_pending_on_public_flip()
RETURNS TRIGGER AS $$
BEGIN
  IF OLD.is_private = TRUE AND NEW.is_private = FALSE THEN
    UPDATE public.follows
       SET status = 'accepted',
           updated_at = NOW()
     WHERE followee_id = NEW.id
       AND status = 'pending';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS auto_accept_pending_on_public_flip_trg ON public.profiles;
CREATE TRIGGER auto_accept_pending_on_public_flip_trg
  AFTER UPDATE OF is_private ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.auto_accept_pending_on_public_flip();

COMMIT;

-- ============================================
-- Verification (run AFTER COMMIT, outside the transaction)
-- ============================================
--   -- All profiles private:
--   SELECT count(*) FILTER (WHERE is_private) AS priv,
--          count(*)                            AS total
--     FROM public.profiles;
--
--   -- Existing accepted follows preserved (compare to a snapshot
--   -- taken before running this migration):
--   SELECT count(*) FROM public.follows WHERE status = 'accepted';
--
--   -- Publication includes follows:
--   SELECT schemaname, tablename
--     FROM pg_publication_tables
--    WHERE pubname = 'supabase_realtime'
--      AND tablename = 'follows';
--
--   -- Privacy-flip trigger installed:
--   SELECT tgname FROM pg_trigger
--    WHERE tgname = 'auto_accept_pending_on_public_flip_trg';
