-- ============================================
-- PR-B: v4 privacy model — rename visibility enum value 'shared' -> 'followers'
-- ============================================
-- See 0. Strategy/spots-newsfeed-activity-model.html §08 (v4 locked) + D22.
--
-- T2 shipped the enum as (private, public); T21.3 added 'shared'. v4 lifts
-- the conflation by renaming 'shared' -> 'followers' and treating
-- list_editors as a fully orthogonal invitation mechanism.
--
-- The rename + the backfill are intentionally split:
--   * Step A renames the enum value. After this, every existing 'shared'
--     row is now valued 'followers' (rename is a label swap; row data is
--     unchanged in storage).
--   * Step B is the default-list backfill (D6): existing TestFlight default
--     lists that landed at visibility='private' under T2 are bumped to
--     'followers' so the social wedge fires immediately.
--
-- Audit query (commented; uncomment + run pre-deploy to verify scope):
--   SELECT visibility, COUNT(*) FROM public.user_lists GROUP BY visibility;

-- Step A — rename the enum value
ALTER TYPE public.list_visibility_enum RENAME VALUE 'shared' TO 'followers';

COMMENT ON TYPE public.list_visibility_enum IS
  'v4 list visibility (private/followers/public). private = owner-only ambient '
  'access (invitees in list_editors still get explicit access). followers = '
  'owner + accepted followers; not discoverable to strangers. public = '
  'discoverable via Discover/share-link, gated by profiles.is_private for '
  'strangers. list_editors is an orthogonal invitation mechanism that works '
  'on top of any visibility level.';

-- Step B — default-list backfill (D6)
-- Bump existing Favorites/Liked/Want-to-Go rows from 'private' to 'followers'
-- so the social wedge fires immediately for current TestFlight users.
-- Custom lists keep visibility='private' (New List UI default).
UPDATE public.user_lists
   SET visibility = 'followers'
 WHERE kind IN ('favorites', 'liked', 'want_to_go')
   AND visibility = 'private';

-- Verify backfill (no diagnostic needed — row count is whatever it is).
COMMENT ON COLUMN public.user_lists.visibility IS
  'v4 list visibility. Default ''private''; default-list seeds (favorites/liked/'
  'want_to_go) land at ''followers'' via guard_create_default_lists_rpc post-PR-B. '
  'Custom lists default to ''private'' in the New List UI.';
