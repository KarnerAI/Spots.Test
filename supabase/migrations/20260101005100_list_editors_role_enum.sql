-- ============================================
-- PR-B: tighten list_editors.role to enum(editor, viewer) — D10
-- ============================================
-- Phase 1 created list_editors.role as TEXT NOT NULL DEFAULT 'editor' for
-- forward-compat. Per eng-review D10, lock it down to a typed enum so the
-- collaboration model has a finite, queryable role set as T4 ships
-- (collaboration UI). 'editor' = write access; 'viewer' = read-only invitee.
--
-- All existing rows are 'editor' (T4 hasn't shipped, no other writes hit
-- this column). The USING clause handles any stragglers explicitly.

CREATE TYPE public.list_editor_role_enum AS ENUM (
  'editor',
  'viewer'
);

COMMENT ON TYPE public.list_editor_role_enum IS
  'Role of a list_editors invitee. editor = write access (insert/delete '
  'spot_list_items, update list metadata). viewer = read-only invitee, '
  'access granted on lists at any visibility level (incl. private).';

-- Drop the column default so the type change isn't blocked by the literal
-- 'editor'::text default, then re-apply the default with the new type.
ALTER TABLE public.list_editors
  ALTER COLUMN role DROP DEFAULT;

ALTER TABLE public.list_editors
  ALTER COLUMN role TYPE public.list_editor_role_enum
  USING role::public.list_editor_role_enum;

ALTER TABLE public.list_editors
  ALTER COLUMN role SET DEFAULT 'editor'::public.list_editor_role_enum;

COMMENT ON COLUMN public.list_editors.role IS
  'editor (default) = write access; viewer = read-only. Independent of '
  'list visibility — invitees get explicit access regardless.';
