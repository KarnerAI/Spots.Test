-- ============================================
-- PR-B: feed_activities table — D2 + D18b + v3
-- ============================================
-- The canonical "first save" / "conversion" record per (user, spot, kind).
-- Drives the Newsfeed feed RPC; replaces the prior pattern of scanning
-- spot_list_items for activity (which produced false re-fires on every
-- organizational move).
--
-- Shape per the locked plan §07.1:
--   * list_ids UUID[] only — no denormalized list metadata, joined at read
--     time so list renames stay consistent (D2).
--   * kind TEXT with a CHECK constraint instead of a Postgres enum, so
--     future activity types (like, comment, follow) get appended by
--     editing the CHECK without an enum migration (§07.5).
--   * UNIQUE(user_id, spot_id, kind) per v3 — allows BOTH a spot_save row
--     AND a conversion row to coexist for the same (user, spot), so
--     Scenario E (WTG -> Favorites/Liked) surfaces two cards in the
--     follower's timeline (D18b + v3 Scenario E reversal).
--
-- RLS shape: owner reads + writes own rows; follower reads happen via the
-- get_following_feed RPC (refactored in 20260101005400). The follower-read
-- access path is intentionally narrow: it goes through the RPC, never via
-- direct table SELECT. That keeps the per-viewer privacy CTE in §07.5 the
-- single source of truth for "who sees what card."

CREATE TABLE public.feed_activities (
  id          UUID NOT NULL PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  spot_id     TEXT NOT NULL REFERENCES public.spots(place_id) ON DELETE CASCADE,
  kind        TEXT NOT NULL CHECK (kind IN ('spot_save', 'conversion')),
  list_ids    UUID[] NOT NULL,
  source      public.spot_list_item_source_enum NOT NULL DEFAULT 'manual',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT feed_activities_unique_per_kind UNIQUE (user_id, spot_id, kind)
);

CREATE INDEX feed_activities_actor_created_idx
  ON public.feed_activities (user_id, created_at DESC);

CREATE INDEX feed_activities_created_idx
  ON public.feed_activities (created_at DESC);

COMMENT ON TABLE public.feed_activities IS
  'Canonical per-(user, spot, kind) feed event record (PR-B). spot_save '
  'rows are written by record_first_save on the first MANUAL save (D15). '
  'conversion rows are written by the list_moves -> feed_activities '
  'trigger when a WTG row converts to favorites/liked (v3 Scenario E + '
  'D20). UNIQUE constraint per v3 lets both kinds coexist for the same '
  '(user, spot) so Pat sees the journey, not just the latest snapshot.';

COMMENT ON COLUMN public.feed_activities.list_ids IS
  'Array of destination list IDs captured at write time. The feed RPC '
  'per-viewer privacy CTE filters this array against list visibility + '
  'follow status; if the filtered array is empty, the row is suppressed '
  'entirely from the viewer''s feed (§07.5).';

COMMENT ON COLUMN public.feed_activities.kind IS
  'Activity kind. CHECK constraint instead of enum so future kinds (like, '
  'comment, follow) extend without a type migration (§07.5).';

COMMENT ON COLUMN public.feed_activities.source IS
  'Provenance of the underlying save. Only ''manual'' rows are written for '
  'kind=spot_save (D15 — imports never fire feed activity).';

-- ============================================
-- RLS
-- ============================================
ALTER TABLE public.feed_activities ENABLE ROW LEVEL SECURITY;

-- Owner reads own rows directly (used by tests + future "my activity" UI).
CREATE POLICY "feed_activities: owner reads own"
  ON public.feed_activities
  FOR SELECT
  USING (user_id = auth.uid());

-- Owner writes own rows. record_first_save runs SECURITY DEFINER (it
-- needs to write rows on behalf of users without round-tripping through
-- RLS twice). This policy covers direct INSERTs (tests + edge cases).
CREATE POLICY "feed_activities: owner writes own"
  ON public.feed_activities
  FOR INSERT
  WITH CHECK (user_id = auth.uid());

-- DELETE happens via the deferred cleanup trigger (SECURITY DEFINER) — no
-- direct user DELETE path. No policy needed; trigger bypasses RLS.
