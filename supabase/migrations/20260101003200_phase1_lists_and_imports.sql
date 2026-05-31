-- ============================================
-- Phase 1: Lists & Imports — Single Migration
-- ============================================
-- Ticket T2 / Decision E1: ONE migration covering all Phase 1 + Phase 3
-- columns so we never need to backfill later.
--
-- This migration:
--   1. Renames the legacy `list_type_enum` to `list_kind_enum` and
--      renames its values to match user-facing semantics:
--        starred     -> favorites   (elite love tier)
--        favorites   -> liked       (mid love tier)
--        bucket_list -> want_to_go  (wishlist)
--      Adds new values: custom, trip, date_plan.
--      Implementation: create a new enum type, add a new `kind` column,
--      backfill from `list_type`, drop the old column and old enum type.
--      Safer than in-place ALTER TYPE for an existing column.
--
--   2. Adds new columns to `user_lists`:
--        visibility       (enum private/public, default private, NOT NULL)
--        share_slug       (text UNIQUE; nanoid 10, server-generated)
--        invite_token     (text UNIQUE; nanoid, server-generated on demand)
--        start_date       (date, nullable; for trips/date_plans)
--        end_date         (date, nullable; for trips/date_plans)
--        cover_image_url  (text, nullable)
--        cover_emoji      (text, nullable)
--
--   3. Adds `source` enum on `spot_list_items` capturing save-provenance
--      (E8). Default `manual`; imports set per-source values.
--
--   4. Creates `list_editors` join table for lightweight collaboration
--      (E6). Owner + invite-redeemed editors can write to the list.
--
--   5. Creates `list_moves` event log for spot conversions across lists
--      (E4). Captures `want_to_go -> favorites|liked` signal for Newsfeed
--      activities and Phase 3 AI planner training.
--
--   6. Adds RPC `move_spot_between_lists` that wraps the spot_list_items
--      move + list_moves insert. The list_moves insert is wrapped in an
--      EXCEPTION block so log failure never aborts the move (E4 failure
--      mode requirement).
--
--   7. Updates `user_lists` and `spot_list_items` RLS policies so list
--      editors (rows in `list_editors`) can read/write the list.
--
-- Filter perf indexes (E11) are intentionally deferred to the ticket that
-- ships filter UI (T8) — without the actual filter query shape we'd be
-- guessing at column orders. The migration here is schema scaffolding
-- only.
--
-- Run order: apply AFTER create_location_saving_schema.sql and
-- guard_create_default_lists_rpc.sql. Apply BEFORE
-- extend_guard_create_default_lists_rpc.sql (it depends on the new `kind`
-- column existing).

BEGIN;

-- ============================================
-- Step 1: Create new enums
-- ============================================

CREATE TYPE public.list_kind_enum AS ENUM (
  'favorites',
  'liked',
  'want_to_go',
  'custom',
  'trip',
  'date_plan'
);

COMMENT ON TYPE public.list_kind_enum IS
  'Semantic kind of a user list. Replaces the legacy list_type_enum '
  '(starred/favorites/bucket_list). The first three values map to the '
  '3 default system lists (Favorites/Liked/Want to Go); custom is the '
  'default for user-created lists; trip and date_plan are reserved for '
  'Phase 3 features and use start_date/end_date.';

CREATE TYPE public.list_visibility_enum AS ENUM (
  'private',
  'public'
);

COMMENT ON TYPE public.list_visibility_enum IS
  'Controls whether a list is visible to other users via its share_slug. '
  'Default private. Public lists are readable by anyone with the slug.';

CREATE TYPE public.spot_list_item_source_enum AS ENUM (
  'manual',
  'import_instagram',
  'import_google_maps',
  'import_apple_notes',
  'import_substack',
  'import_voice',
  'import_text',
  'import_yelp',
  'import_beli'
);

COMMENT ON TYPE public.spot_list_item_source_enum IS
  'Provenance of a spot save (decision E8). manual = user-driven save; '
  'import_* = bulk import from the named source. Feeds analytics for '
  '"which import sources actually convert?"';

-- ============================================
-- Step 2: Add new columns to user_lists
-- ============================================

ALTER TABLE public.user_lists
  ADD COLUMN kind            public.list_kind_enum,
  ADD COLUMN visibility      public.list_visibility_enum NOT NULL DEFAULT 'private',
  ADD COLUMN share_slug      TEXT,
  ADD COLUMN invite_token    TEXT,
  ADD COLUMN start_date      DATE,
  ADD COLUMN end_date        DATE,
  ADD COLUMN cover_image_url TEXT,
  ADD COLUMN cover_emoji     TEXT;

COMMENT ON COLUMN public.user_lists.kind IS
  'Semantic kind. Replaces list_type. favorites/liked/want_to_go are '
  'the 3 default system lists; custom is the default for user-created '
  'lists; trip/date_plan are Phase 3.';
COMMENT ON COLUMN public.user_lists.visibility IS
  'private (default) or public. Public lists are readable by anyone '
  'with the share_slug.';
COMMENT ON COLUMN public.user_lists.share_slug IS
  'Random nanoid (10 chars). Server-generated. Unguessable, so the '
  'enumeration risk on public lists is bounded.';
COMMENT ON COLUMN public.user_lists.invite_token IS
  'Single invite token for the lightweight collaboration link (E6). '
  'Redeeming the link inserts a row in list_editors.';
COMMENT ON COLUMN public.user_lists.start_date IS
  'Trip / date_plan start date. NULL for non-trip lists.';
COMMENT ON COLUMN public.user_lists.end_date IS
  'Trip / date_plan end date. NULL for non-trip lists.';
COMMENT ON COLUMN public.user_lists.cover_image_url IS
  'Cover photo for the list. Used in the public share-link view and '
  'list cards.';
COMMENT ON COLUMN public.user_lists.cover_emoji IS
  'Optional emoji used as the list icon when no cover photo is set.';

-- ============================================
-- Step 3: Backfill `kind` from legacy `list_type`
-- ============================================
-- starred     -> favorites   (elite love tier was always displayed as "Favorites")
-- favorites   -> liked       (mid love tier was always displayed as "Liked")
-- bucket_list -> want_to_go  (wishlist was always displayed as "Want to Go")
-- NULL        -> custom      (user-created lists)

UPDATE public.user_lists
SET kind = CASE list_type
  WHEN 'starred'     THEN 'favorites'::public.list_kind_enum
  WHEN 'favorites'   THEN 'liked'::public.list_kind_enum
  WHEN 'bucket_list' THEN 'want_to_go'::public.list_kind_enum
  ELSE                    'custom'::public.list_kind_enum
END;

-- Verify backfill (should be zero rows with kind IS NULL)
DO $$
DECLARE
  null_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO null_count FROM public.user_lists WHERE kind IS NULL;
  IF null_count > 0 THEN
    RAISE EXCEPTION 'Backfill incomplete: % user_lists rows have kind IS NULL', null_count;
  END IF;
END $$;

-- ============================================
-- Step 4: Drop old constraints / indexes / policies that reference list_type
-- ============================================

ALTER TABLE public.user_lists
  DROP CONSTRAINT IF EXISTS user_lists_unique_system_list;

ALTER TABLE public.user_lists
  DROP CONSTRAINT IF EXISTS user_lists_name_or_type_check;

DROP INDEX IF EXISTS public.user_lists_user_type_idx;

DROP POLICY IF EXISTS "Users can delete own custom lists" ON public.user_lists;

-- ============================================
-- Step 5: Drop legacy list_type column + enum type
-- ============================================

ALTER TABLE public.user_lists DROP COLUMN list_type;
DROP TYPE public.list_type_enum;

-- ============================================
-- Step 6: Lock down `kind` — NOT NULL + default
-- ============================================

ALTER TABLE public.user_lists
  ALTER COLUMN kind SET NOT NULL,
  ALTER COLUMN kind SET DEFAULT 'custom';

-- Each user has at most one of each system list kind (favorites / liked /
-- want_to_go). custom / trip / date_plan can repeat per user.
CREATE UNIQUE INDEX user_lists_unique_system_kind_idx
  ON public.user_lists (user_id, kind)
  WHERE kind IN ('favorites', 'liked', 'want_to_go');

-- Replacement for the dropped user_lists_user_type_idx — fast lookup of
-- a user's default lists by kind.
CREATE INDEX user_lists_user_kind_idx
  ON public.user_lists (user_id, kind);

-- Custom lists require a name; system kinds (favorites/liked/want_to_go)
-- use the kind value as their display label and may have NULL name.
ALTER TABLE public.user_lists
  ADD CONSTRAINT user_lists_name_required_for_custom_check CHECK (
    kind IN ('favorites', 'liked', 'want_to_go') OR name IS NOT NULL
  );

-- share_slug and invite_token must be unique when set.
CREATE UNIQUE INDEX user_lists_share_slug_idx
  ON public.user_lists (share_slug)
  WHERE share_slug IS NOT NULL;

CREATE UNIQUE INDEX user_lists_invite_token_idx
  ON public.user_lists (invite_token)
  WHERE invite_token IS NOT NULL;

-- Trip date sanity: end_date must be >= start_date if both set.
ALTER TABLE public.user_lists
  ADD CONSTRAINT user_lists_date_range_check CHECK (
    start_date IS NULL OR end_date IS NULL OR end_date >= start_date
  );

-- Recreate the system-list DELETE policy against the new column. Users
-- may delete custom / trip / date_plan lists they own, but not the 3
-- default system kinds.
CREATE POLICY "Users can delete own non-system lists"
  ON public.user_lists
  FOR DELETE
  USING (
    auth.uid() = user_id
    AND kind NOT IN ('favorites', 'liked', 'want_to_go')
  );

-- ============================================
-- Step 7: Add `source` column to spot_list_items
-- ============================================

ALTER TABLE public.spot_list_items
  ADD COLUMN source public.spot_list_item_source_enum NOT NULL DEFAULT 'manual';

COMMENT ON COLUMN public.spot_list_items.source IS
  'How this spot landed in this list (decision E8). manual = user '
  'saved it directly; import_* values capture which bulk-import flow '
  'created the row. Feeds conversion analytics.';

-- ============================================
-- Step 8: list_editors — lightweight collaboration (E6)
-- ============================================

CREATE TABLE public.list_editors (
  list_id    UUID NOT NULL REFERENCES public.user_lists(id) ON DELETE CASCADE,
  user_id    UUID NOT NULL REFERENCES auth.users(id)        ON DELETE CASCADE,
  role       TEXT NOT NULL DEFAULT 'editor',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (list_id, user_id)
);

CREATE INDEX list_editors_user_id_idx ON public.list_editors(user_id);

COMMENT ON TABLE public.list_editors IS
  'Join table for lightweight list collaboration (decision E6). A user '
  'with a row here can write to the list (RLS extends user_lists and '
  'spot_list_items policies). Invite redemption flow inserts these rows '
  'via a SECURITY DEFINER RPC. role left as a free-form text column for '
  'forward compat (viewer/admin/etc).';

ALTER TABLE public.list_editors ENABLE ROW LEVEL SECURITY;

-- SELECT: a user can see their own editor row, and a list owner can see
-- every editor on their list.
CREATE POLICY "Editors and owners can read list_editors"
  ON public.list_editors
  FOR SELECT
  USING (
    user_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.user_lists ul
      WHERE ul.id = list_editors.list_id
        AND ul.user_id = auth.uid()
    )
  );

-- INSERT: only the list owner can directly add an editor (the typical
-- redeem flow goes via SECURITY DEFINER RPC, which bypasses RLS).
CREATE POLICY "Owners can add editors"
  ON public.list_editors
  FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.user_lists ul
      WHERE ul.id = list_editors.list_id
        AND ul.user_id = auth.uid()
    )
  );

-- DELETE: list owner can remove any editor; editor can remove themselves.
CREATE POLICY "Owners or self can remove editors"
  ON public.list_editors
  FOR DELETE
  USING (
    user_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.user_lists ul
      WHERE ul.id = list_editors.list_id
        AND ul.user_id = auth.uid()
    )
  );

-- ============================================
-- Step 9: list_moves — conversion event log (E4)
-- ============================================

CREATE TABLE public.list_moves (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  spot_id      TEXT NOT NULL,  -- not FK: spot may be deleted, log stays
  from_list_id UUID,           -- nullable for first-add events
  to_list_id   UUID,           -- nullable for full-removal events
  from_kind    public.list_kind_enum,
  to_kind      public.list_kind_enum,
  ts           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX list_moves_user_ts_idx ON public.list_moves(user_id, ts DESC);
CREATE INDEX list_moves_spot_idx    ON public.list_moves(spot_id);

COMMENT ON TABLE public.list_moves IS
  'Event log of spot conversions across lists (decision E4). Captures '
  'the want_to_go -> favorites|liked conversion signal for Newsfeed '
  'activities and Phase 3 AI planner training. Inserts here must never '
  'block the parent list move (see move_spot_between_lists RPC).';

ALTER TABLE public.list_moves ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read own list_moves"
  ON public.list_moves
  FOR SELECT
  USING (user_id = auth.uid());

CREATE POLICY "Users can insert own list_moves"
  ON public.list_moves
  FOR INSERT
  WITH CHECK (user_id = auth.uid());

-- ============================================
-- Step 10: Extend user_lists write policies for editors
-- ============================================
-- Existing UPDATE policy ("Users can update own lists") only allows the
-- owner. Replace with a policy that ALSO allows editors. Note: editors
-- get UPDATE on the list itself (e.g. to change name or cover); they
-- cannot delete or change visibility or transfer ownership (the DELETE
-- policy in Step 6 is owner-only, and visibility/user_id changes are
-- structurally owner-only via app-layer convention).

DROP POLICY IF EXISTS "Users can update own lists" ON public.user_lists;

CREATE POLICY "Owners and editors can update lists"
  ON public.user_lists
  FOR UPDATE
  USING (
    auth.uid() = user_id
    OR EXISTS (
      SELECT 1 FROM public.list_editors le
      WHERE le.list_id = user_lists.id
        AND le.user_id = auth.uid()
    )
  );

-- ============================================
-- Step 11: Extend spot_list_items policies for editors
-- ============================================
-- Existing SELECT/INSERT/DELETE policies only allow the list owner.
-- Replace with policies that ALSO allow editors.

DROP POLICY IF EXISTS "Users can view own list items"      ON public.spot_list_items;
DROP POLICY IF EXISTS "Users can add items to own lists"   ON public.spot_list_items;
DROP POLICY IF EXISTS "Users can remove items from own lists" ON public.spot_list_items;

CREATE POLICY "Owners and editors can read list items"
  ON public.spot_list_items
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.user_lists ul
      WHERE ul.id = spot_list_items.list_id
        AND ul.user_id = auth.uid()
    )
    OR EXISTS (
      SELECT 1 FROM public.list_editors le
      WHERE le.list_id = spot_list_items.list_id
        AND le.user_id = auth.uid()
    )
  );

CREATE POLICY "Owners and editors can add list items"
  ON public.spot_list_items
  FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.user_lists ul
      WHERE ul.id = spot_list_items.list_id
        AND ul.user_id = auth.uid()
    )
    OR EXISTS (
      SELECT 1 FROM public.list_editors le
      WHERE le.list_id = spot_list_items.list_id
        AND le.user_id = auth.uid()
    )
  );

CREATE POLICY "Owners and editors can remove list items"
  ON public.spot_list_items
  FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM public.user_lists ul
      WHERE ul.id = spot_list_items.list_id
        AND ul.user_id = auth.uid()
    )
    OR EXISTS (
      SELECT 1 FROM public.list_editors le
      WHERE le.list_id = spot_list_items.list_id
        AND le.user_id = auth.uid()
    )
  );

-- ============================================
-- Step 12: move_spot_between_lists RPC (E4)
-- ============================================
-- Single entry point for moving a spot between lists. Does:
--   (1) DELETE the spot from from_list_id (if non-null)
--   (2) INSERT the spot into to_list_id (if non-null), ON CONFLICT DO NOTHING
--   (3) INSERT a list_moves row capturing the transition — wrapped in
--       EXCEPTION block so a log failure never aborts the move (E4
--       failure mode requirement).
--
-- Authorization: caller must be owner or editor of BOTH from-list and
-- to-list (whichever is non-null). The function is SECURITY DEFINER so
-- it can write list_moves under the caller's auth.uid() without going
-- through RLS twice.

CREATE OR REPLACE FUNCTION public.move_spot_between_lists(
  p_spot_id      TEXT,
  p_from_list_id UUID,
  p_to_list_id   UUID,
  p_source       public.spot_list_item_source_enum DEFAULT 'manual'
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid       UUID := auth.uid();
  v_from_kind public.list_kind_enum;
  v_to_kind   public.list_kind_enum;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'unauthorized: anonymous callers may not move spots';
  END IF;

  IF p_from_list_id IS NULL AND p_to_list_id IS NULL THEN
    RAISE EXCEPTION 'invalid arguments: at least one of from_list_id / to_list_id must be non-null';
  END IF;

  -- Authorization + kind capture for from-list
  IF p_from_list_id IS NOT NULL THEN
    SELECT ul.kind INTO v_from_kind
    FROM public.user_lists ul
    WHERE ul.id = p_from_list_id
      AND (
        ul.user_id = v_uid
        OR EXISTS (
          SELECT 1 FROM public.list_editors le
          WHERE le.list_id = ul.id AND le.user_id = v_uid
        )
      );
    IF NOT FOUND THEN
      RAISE EXCEPTION 'unauthorized: caller is not owner or editor of from_list_id';
    END IF;
  END IF;

  -- Authorization + kind capture for to-list
  IF p_to_list_id IS NOT NULL THEN
    SELECT ul.kind INTO v_to_kind
    FROM public.user_lists ul
    WHERE ul.id = p_to_list_id
      AND (
        ul.user_id = v_uid
        OR EXISTS (
          SELECT 1 FROM public.list_editors le
          WHERE le.list_id = ul.id AND le.user_id = v_uid
        )
      );
    IF NOT FOUND THEN
      RAISE EXCEPTION 'unauthorized: caller is not owner or editor of to_list_id';
    END IF;
  END IF;

  -- Mutate spot_list_items
  IF p_from_list_id IS NOT NULL THEN
    DELETE FROM public.spot_list_items
    WHERE spot_id = p_spot_id AND list_id = p_from_list_id;
  END IF;

  IF p_to_list_id IS NOT NULL THEN
    INSERT INTO public.spot_list_items (spot_id, list_id, source)
    VALUES (p_spot_id, p_to_list_id, p_source)
    ON CONFLICT (spot_id, list_id) DO NOTHING;
  END IF;

  -- Log the conversion. Failure here must NOT abort the move (E4).
  BEGIN
    INSERT INTO public.list_moves (
      user_id, spot_id, from_list_id, to_list_id, from_kind, to_kind
    )
    VALUES (
      v_uid, p_spot_id, p_from_list_id, p_to_list_id, v_from_kind, v_to_kind
    );
  EXCEPTION WHEN OTHERS THEN
    -- Swallow: logging is best-effort. Use RAISE NOTICE so failures
    -- show up in Supabase logs without aborting the transaction.
    RAISE NOTICE 'list_moves insert failed: %', SQLERRM;
  END;
END;
$$;

COMMENT ON FUNCTION public.move_spot_between_lists IS
  'Atomically moves a spot between lists (decision E4). Authorizes '
  'caller as owner or editor of both lists. Logs the transition into '
  'list_moves; log failure never aborts the move.';

-- ============================================
-- Migration complete
-- ============================================
-- Next: apply extend_guard_create_default_lists_rpc.sql to update the
-- default-lists RPC to set `kind` on the 3 default rows.

COMMIT;
