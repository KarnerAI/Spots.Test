-- ============================================
-- PR-B: record_first_save RPC + cleanup trigger + conversion trigger
-- ============================================
-- Three things in one file because they conceptually form one unit:
--   (1) record_first_save: idempotent atomic write of N spot_list_items rows
--       + a feed_activities row, in a single transaction (D3 + D14).
--   (2) Deferred cleanup trigger on spot_list_items DELETE: removes the
--       feed_activities row when the (user, spot) save-set becomes empty
--       (D4 + D5). Deferred so the move RPC's DELETE+INSERT pattern
--       doesn't false-trigger cleanup.
--   (3) Conversion-fire trigger on list_moves INSERT: writes a
--       kind='conversion' feed_activities row when a WTG row converts to
--       favorites/liked (v3 Scenario E + D20 + Q2 answer).

-- ============================================
-- (1) record_first_save
-- ============================================
-- Atomic write path used by LocationSavingViewModel for a manual save.
-- Inserts one spot_list_items row per p_list_ids element (idempotent via
-- the existing UNIQUE(spot_id, list_id) constraint) and a single
-- feed_activities row keyed (user_id, spot_id, kind='spot_save').
--
-- Idempotency:
--   * Re-running with the same args is a no-op (both ON CONFLICT DO NOTHING).
--   * If a prior import already populated some lists, the first MANUAL
--     call still fires the feed card (D15) — the dedupe key includes
--     only feed_activities, not spot_list_items.
--
-- The feed_activities INSERT is skipped entirely for import sources
-- (D15 + scenario G — imports never fire feed activity).

CREATE OR REPLACE FUNCTION public.record_first_save(
  p_spot_id  TEXT,
  p_list_ids UUID[],
  p_source   public.spot_list_item_source_enum DEFAULT 'manual'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid          UUID := auth.uid();
  v_list_id      UUID;
  v_activity_id  UUID;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'unauthorized: anonymous callers may not save spots';
  END IF;

  IF p_list_ids IS NULL OR array_length(p_list_ids, 1) IS NULL THEN
    RAISE EXCEPTION 'invalid arguments: p_list_ids must contain at least one list_id';
  END IF;

  -- Authorize each target list — caller must be owner or editor.
  -- This loop replaces the per-list authorization that previously lived
  -- in the VM's per-list saveSpot() call site (D14: batch into one RPC).
  FOREACH v_list_id IN ARRAY p_list_ids LOOP
    IF NOT EXISTS (
      SELECT 1 FROM public.user_lists ul
      WHERE ul.id = v_list_id
        AND (
          ul.user_id = v_uid
          OR EXISTS (
            SELECT 1 FROM public.list_editors le
            WHERE le.list_id = ul.id AND le.user_id = v_uid
          )
        )
    ) THEN
      RAISE EXCEPTION 'unauthorized: caller is not owner or editor of list_id %', v_list_id;
    END IF;
  END LOOP;

  -- (a) Insert one spot_list_items row per target list. Idempotent via
  --     the existing UNIQUE(spot_id, list_id) constraint.
  FOREACH v_list_id IN ARRAY p_list_ids LOOP
    INSERT INTO public.spot_list_items (spot_id, list_id, source)
    VALUES (p_spot_id, v_list_id, p_source)
    ON CONFLICT (spot_id, list_id) DO NOTHING;
  END LOOP;

  -- (b) Insert the feed_activities row (kind='spot_save'), but ONLY for
  --     manual saves. Imports never fire feed activity (D15 + scenario G).
  --     ON CONFLICT DO NOTHING handles the "first MANUAL save after a
  --     prior MANUAL save attempt" idempotency case (re-run of the same
  --     intent — picker re-save with the same list set).
  IF p_source = 'manual' THEN
    INSERT INTO public.feed_activities (user_id, spot_id, kind, list_ids, source)
    VALUES (v_uid, p_spot_id, 'spot_save', p_list_ids, p_source)
    ON CONFLICT (user_id, spot_id, kind) DO NOTHING
    RETURNING id INTO v_activity_id;
  END IF;

  RETURN v_activity_id;  -- NULL when the insert was a no-op (idempotent re-run or import).
END;
$$;

COMMENT ON FUNCTION public.record_first_save IS
  'Atomic batched first-save RPC (D3 + D14). Writes spot_list_items rows '
  'for all p_list_ids and one feed_activities row keyed (user, spot, '
  'spot_save). Idempotent. Import sources skip the feed_activities write '
  '(D15 + Scenario G). Auth: caller must be owner/editor of every target list.';

-- ============================================
-- (2) Deferred cleanup trigger on spot_list_items DELETE
-- ============================================
-- WHY DEFERRED:
--   The move_spot_between_lists RPC does DELETE (from old list) + INSERT
--   (into new list) in one transaction. If this trigger fired immediately
--   on the DELETE, it would see (user, spot) save-count = 0 at the moment
--   the DELETE statement ran (the INSERT happens later in the same
--   transaction) and would incorrectly delete the feed_activities row.
--
--   CONSTRAINT TRIGGER ... DEFERRABLE INITIALLY DEFERRED fires at COMMIT,
--   by which time the INSERT has landed and the save-count is correct.
--   A move (DELETE+INSERT) → net count unchanged → trigger no-ops.
--   A full un-save (DELETE with no compensating INSERT) → net count
--   becomes 0 → feed_activities row deleted.
--
--   The eng review (§09) flagged the "deferred trigger no-op during move
--   RPC" pattern as a MANDATORY regression test (covered in
--   FeedActivityIntegrationTests).
--
--   Do NOT "fix" this trigger to immediate / row-level / etc. The
--   deferral is load-bearing for Scenario F (Favorites -> Liked stays
--   silent because the move keeps net count > 0).

CREATE OR REPLACE FUNCTION public.feed_activities_cleanup_on_save_empty()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_remaining INTEGER;
  v_user_id   UUID;
BEGIN
  -- Resolve the spot's owner via the deleted row's list -> user_lists.
  -- We have to query user_lists because spot_list_items doesn't carry
  -- user_id directly (it's derivable via list_id but the list may also
  -- have been cascaded-deleted if a whole list got removed).
  --
  -- OLD.list_id may already be gone (CASCADE from user_lists DELETE).
  -- That's fine — the user_lists DELETE itself was the user un-saving
  -- the entire list, and feed_activities for any (user, spot) pair
  -- where the spot was only in that list will become orphaned and need
  -- cleanup. We handle that by scanning user_lists for ALL lists this
  -- user owns and counting non-zero memberships.
  SELECT ul.user_id INTO v_user_id
  FROM public.user_lists ul
  WHERE ul.id = OLD.list_id;

  IF v_user_id IS NULL THEN
    -- List itself was deleted; resolve the user another way — find the
    -- feed_activities row for this spot and use its user_id.
    SELECT fa.user_id INTO v_user_id
    FROM public.feed_activities fa
    WHERE fa.spot_id = OLD.spot_id
    LIMIT 1;

    IF v_user_id IS NULL THEN
      RETURN OLD;  -- nothing to clean up
    END IF;
  END IF;

  -- Count any remaining spot_list_items rows for this (user, spot) pair
  -- across all of the user's lists. If zero, cleanup is appropriate.
  SELECT COUNT(*) INTO v_remaining
  FROM public.spot_list_items sli
  JOIN public.user_lists ul ON ul.id = sli.list_id
  WHERE ul.user_id = v_user_id
    AND sli.spot_id = OLD.spot_id;

  IF v_remaining = 0 THEN
    DELETE FROM public.feed_activities
    WHERE user_id = v_user_id
      AND spot_id = OLD.spot_id;
  END IF;

  RETURN OLD;
END;
$$;

COMMENT ON FUNCTION public.feed_activities_cleanup_on_save_empty IS
  'Deferred-trigger cleanup body. Resolves (user, spot) save count at '
  'COMMIT time; deletes feed_activities row only when count hits zero. '
  'See trigger comment for why this MUST stay deferred (move RPC pattern).';

CREATE CONSTRAINT TRIGGER feed_activities_cleanup_trg
  AFTER DELETE ON public.spot_list_items
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION public.feed_activities_cleanup_on_save_empty();

COMMENT ON TRIGGER feed_activities_cleanup_trg ON public.spot_list_items IS
  'Deferred cleanup of feed_activities when a (user, spot) save-set goes '
  'empty (D4 + D5). DEFERRABLE INITIALLY DEFERRED so the move RPC''s '
  'DELETE+INSERT pattern doesn''t false-trigger cleanup — the deferred '
  'fire sees post-COMMIT state with the destination INSERT already in '
  'place. The eng review (§09) flagged this as a MANDATORY regression '
  'test; do NOT change to immediate/row-level fire mode without '
  'updating the test fixture.';

-- ============================================
-- (3) Conversion-fire trigger on list_moves INSERT
-- ============================================
-- v3 Scenario E reversal + D20: WTG -> Favorites/Liked transitions DO
-- fire a new feed card. The "I went there a month later" moment is
-- engagement-worthy. Both the original spot_save card AND the new
-- conversion card live in the timeline (per the v3 + D18b UNIQUE
-- constraint on (user_id, spot_id, kind)).
--
-- Only WTG -> Favorites/Liked qualifies; other moves (Favorites <-> Liked,
-- adding to custom lists, etc.) stay silent per D20.
--
-- The list_moves write itself happens inside move_spot_between_lists,
-- which is the canonical conversion entry point. Firing here means the
-- conversion card writing is centralized at the DB layer — no Swift
-- call site needs to change (Q2 answer).

CREATE OR REPLACE FUNCTION public.feed_activities_fire_conversion()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.from_kind = 'want_to_go'
     AND NEW.to_kind IN ('favorites', 'liked')
     AND NEW.to_list_id IS NOT NULL
  THEN
    INSERT INTO public.feed_activities (user_id, spot_id, kind, list_ids, source)
    VALUES (NEW.user_id, NEW.spot_id, 'conversion', ARRAY[NEW.to_list_id], 'manual')
    ON CONFLICT (user_id, spot_id, kind) DO NOTHING;
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.feed_activities_fire_conversion IS
  'On list_moves INSERT for WTG -> favorites/liked, writes a kind=conversion '
  'feed_activities row (v3 Scenario E + D20). Idempotent via the (user, '
  'spot, kind) UNIQUE constraint — repeated conversions for the same '
  '(user, spot) are no-ops, so the user can move WTG -> Favorites -> '
  'Favorites without spamming the feed.';

CREATE TRIGGER feed_activities_fire_conversion_trg
  AFTER INSERT ON public.list_moves
  FOR EACH ROW
  EXECUTE FUNCTION public.feed_activities_fire_conversion();

COMMENT ON TRIGGER feed_activities_fire_conversion_trg ON public.list_moves IS
  'Fires the v3 conversion card. Non-deferred — list_moves inserts are '
  'standalone (the move RPC swallows logging failures via EXCEPTION), so '
  'there''s no DELETE+INSERT pattern to dodge here.';
