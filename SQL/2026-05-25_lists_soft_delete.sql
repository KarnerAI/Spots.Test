-- ============================================
-- T21.1: Soft-delete for custom lists
-- ============================================
-- Adds tombstone column + active_user_lists view + composite index
-- + soft_delete_list / restore_list RPCs.
--
-- Per decision D-T21.2 in /plan-eng-review on 2026-05-25:
--
-- Soft-delete pattern: instead of removing rows, set deleted_at = NOW()
-- when the user taps Delete. The list disappears from Swift queries
-- (which read from active_user_lists), but the data is preserved for
-- 30 days so the user can restore from Settings.
--
-- The view enforces filtering at the schema layer — it's impossible
-- for new code to accidentally surface tombstoned rows because the
-- "table" they read from doesn't include them.
--
-- Out-of-band: a nightly cron job (pg_cron, set up separately) DELETEs
-- rows where deleted_at < NOW() - INTERVAL '30 days'. The existing
-- ON DELETE CASCADE on list_editors, list_moves, and spot_list_items
-- handles permanent purge of dependent rows.

BEGIN;

-- ============================================
-- Step 1: Add deleted_at column
-- ============================================

ALTER TABLE public.user_lists
  ADD COLUMN deleted_at TIMESTAMPTZ NULL;

COMMENT ON COLUMN public.user_lists.deleted_at IS
  'Soft-delete tombstone. NULL = active. Non-NULL = the user tapped '
  'Delete at that timestamp. Hidden from active_user_lists view. '
  'Hard-purged by nightly cron after 30 days.';

-- ============================================
-- Step 2: Composite partial index for fast active-row lookups
-- ============================================
-- Most reads filter by user_id and skip tombstoned rows. A partial
-- index on (user_id) WHERE deleted_at IS NULL keeps the index small
-- and lets Postgres scan straight to active rows.

CREATE INDEX user_lists_user_active_idx
  ON public.user_lists (user_id)
  WHERE deleted_at IS NULL;

-- ============================================
-- Step 3: active_user_lists view
-- ============================================
-- The read source for everything UI-facing. Use security_invoker so
-- the view respects the calling user's RLS (does not bypass).

CREATE VIEW public.active_user_lists
  WITH (security_invoker = true) AS
  SELECT * FROM public.user_lists WHERE deleted_at IS NULL;

COMMENT ON VIEW public.active_user_lists IS
  'Active (non-tombstoned) user lists. UI reads go through this view; '
  'restore RPC and admin paths query user_lists directly. Created '
  '2026-05-25 per T21.1 / decision D-T21.2.';

GRANT SELECT ON public.active_user_lists TO authenticated;

-- ============================================
-- Step 4: soft_delete_list RPC — owner-only, no system kinds
-- ============================================
-- Returns the now-tombstoned row so the client can show "Restore"
-- banner copy with the deleted_at timestamp.

CREATE OR REPLACE FUNCTION public.soft_delete_list(p_list_id UUID)
RETURNS public.user_lists
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_list public.user_lists;
BEGIN
  -- Ownership + kind check. System lists (favorites/liked/want_to_go)
  -- can't be deleted at all. Already-deleted lists return error.
  SELECT * INTO v_list
    FROM public.user_lists
    WHERE id = p_list_id
      AND user_id = auth.uid()
      AND kind NOT IN ('favorites', 'liked', 'want_to_go')
      AND deleted_at IS NULL;

  IF v_list.id IS NULL THEN
    RAISE EXCEPTION
      'List not found, not owned by you, a default list, or already deleted'
      USING ERRCODE = '42501';
  END IF;

  UPDATE public.user_lists
    SET deleted_at = NOW()
    WHERE id = p_list_id
    RETURNING * INTO v_list;

  RETURN v_list;
END;
$$;

GRANT EXECUTE ON FUNCTION public.soft_delete_list(UUID) TO authenticated;

COMMENT ON FUNCTION public.soft_delete_list(UUID) IS
  'Owner-only soft-delete. Sets deleted_at = NOW() on the list. '
  'Returns the updated row. Rejects: not-owner, system kinds, '
  'already-deleted lists. 30-day restore window enforced by '
  'restore_list RPC + nightly purge cron.';

-- ============================================
-- Step 5: restore_list RPC — within 30-day window
-- ============================================

CREATE OR REPLACE FUNCTION public.restore_list(p_list_id UUID)
RETURNS public.user_lists
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_list public.user_lists;
BEGIN
  SELECT * INTO v_list
    FROM public.user_lists
    WHERE id = p_list_id
      AND user_id = auth.uid()
      AND deleted_at IS NOT NULL
      AND deleted_at > NOW() - INTERVAL '30 days';

  IF v_list.id IS NULL THEN
    RAISE EXCEPTION
      'List not found, not owned by you, not deleted, or past 30-day recovery window'
      USING ERRCODE = '42501';
  END IF;

  UPDATE public.user_lists
    SET deleted_at = NULL
    WHERE id = p_list_id
    RETURNING * INTO v_list;

  RETURN v_list;
END;
$$;

GRANT EXECUTE ON FUNCTION public.restore_list(UUID) TO authenticated;

COMMENT ON FUNCTION public.restore_list(UUID) IS
  'Owner-only restore of a soft-deleted list, only within the 30-day '
  'recovery window. Sets deleted_at = NULL. Rejects past-window or '
  'non-deleted lists. Cron purges rows older than 30 days, after '
  'which restore is impossible.';

-- ============================================
-- Step 6: list_deleted_lists RPC — for the "Recently deleted" UI
-- ============================================
-- Returns the calling user's tombstoned lists, ordered newest-first,
-- with days_remaining computed so the UI can render an urgency banner.

CREATE OR REPLACE FUNCTION public.list_deleted_lists()
RETURNS TABLE (
  id UUID,
  name TEXT,
  kind TEXT,
  cover_emoji TEXT,
  cover_image_url TEXT,
  deleted_at TIMESTAMPTZ,
  days_remaining INTEGER
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    ul.id,
    ul.name,
    ul.kind::text,
    ul.cover_emoji,
    ul.cover_image_url,
    ul.deleted_at,
    GREATEST(
      0,
      30 - EXTRACT(DAY FROM (NOW() - ul.deleted_at))::INTEGER
    ) AS days_remaining
  FROM public.user_lists ul
  WHERE ul.user_id = auth.uid()
    AND ul.deleted_at IS NOT NULL
    AND ul.deleted_at > NOW() - INTERVAL '30 days'
  ORDER BY ul.deleted_at DESC;
$$;

GRANT EXECUTE ON FUNCTION public.list_deleted_lists() TO authenticated;

COMMENT ON FUNCTION public.list_deleted_lists() IS
  'Returns the calling user''s tombstoned lists within the 30-day '
  'restore window, with computed days_remaining. Powers the '
  '"Recently deleted" section in Settings.';

COMMIT;
