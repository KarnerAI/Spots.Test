-- ============================================
-- T21 QA round 2: add description column to user_lists
-- ============================================
-- Adds a free-form description field per user request: Maya wants to add
-- context to her custom lists ("Best taquerias on Calle Madero", "Trip
-- planning for August 2026", etc.). Default lists (Favorites / Liked /
-- Want to go) get hardcoded descriptions in Swift and ignore this column.
--
-- The active_user_lists VIEW from 2026-05-25_lists_soft_delete.sql does
-- `SELECT * FROM user_lists`, so it picks up the new column automatically —
-- no view recreate needed.

BEGIN;

ALTER TABLE public.user_lists
  ADD COLUMN description TEXT NULL;

COMMENT ON COLUMN public.user_lists.description IS
  'User-supplied description for custom lists. NULL = no description. '
  'System kinds (favorites/liked/want_to_go) ignore this column and use '
  'hardcoded copy in the Swift client. Max length enforced at the '
  'service layer (500 chars) — no DB constraint because the truncation '
  'message should be user-facing, not a 23xxx error code.';

-- Recreate active_user_lists view to pick up the new column. SELECT *
-- in the view body normally cascades, but Postgres caches the view
-- column list at creation time, so an explicit DROP + CREATE is safer.
DROP VIEW IF EXISTS public.active_user_lists;
CREATE VIEW public.active_user_lists
  WITH (security_invoker = true) AS
  SELECT * FROM public.user_lists WHERE deleted_at IS NULL;

COMMENT ON VIEW public.active_user_lists IS
  'Active (non-tombstoned) user lists. UI reads go through this view; '
  'restore RPC and admin paths query user_lists directly. Recreated '
  '2026-05-25 (T21 QA round 2) to pick up the new description column.';

GRANT SELECT ON public.active_user_lists TO authenticated;

COMMIT;
