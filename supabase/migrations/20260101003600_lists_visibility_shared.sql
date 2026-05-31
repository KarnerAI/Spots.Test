-- ============================================
-- T21.3: Extend list_visibility_enum with 'shared'
-- ============================================
-- Reopens E1 — visibility is now 3-state: private / shared / public.
--
-- Per the revised E1 in /plan-eng-review on 2026-05-25:
--   private — only the owner sees it (default)
--   shared  — owner + invited collaborators (list_editors). Not
--             publicly discoverable.
--   public  — visible via share link to anyone; surfaces in Discover.
--             Independent of list_editors.
--
-- visibility state and collaboration are orthogonal in the data model
-- but coupled in UX: a list with non-empty list_editors displays the
-- "Shared" badge even if its underlying visibility is 'private'.
-- That derivation happens in Swift (UserList.swift).
--
-- T2 migration shipped 2026-05-23 — this is the follow-up to extend
-- the enum type. ALTER TYPE ADD VALUE is non-blocking and safe on a
-- live database, but cannot run inside a transaction (per Postgres
-- docs). Do NOT wrap in BEGIN/COMMIT.

ALTER TYPE public.list_visibility_enum ADD VALUE IF NOT EXISTS 'shared'
  BEFORE 'public';

COMMENT ON TYPE public.list_visibility_enum IS
  'List visibility (revised 2026-05-25, decision E1 v2). Values in '
  'order: private (owner-only, default), shared (owner + invited '
  'editors via list_editors), public (anyone with link; Discover '
  'surface). Shared and list_editors are orthogonal in data but '
  'coupled in UX — Swift derives "effective" visibility for badges.';
