-- ============================================
-- Save-velocity instrumentation (T1, Phase 1 Lane D)
-- ============================================
-- Run in Supabase Dashboard → Database → SQL Editor.
-- Idempotent and reversible.
--
-- PURPOSE
-- Establishes the saves/user/week baseline needed for Phase 2 readiness
-- ("avg 20+ saves/user"). Ships backend-only so the baseline accumulates
-- while the rest of Phase 1 is built.
--
-- DESIGN
--   1. New `save_events` table — one row per insert into spot_list_items.
--   2. AFTER INSERT trigger on `spot_list_items` resolves the owning user
--      from user_lists and emits the event. Server-side single source of
--      truth: manual saves, future /import edge-function inserts, and any
--      RPC writing into spot_list_items all flow through here.
--   3. Aggregation view `saves_per_user_7d` exposing median/p10/p90.
--   4. Trigger emission is wrapped in EXCEPTION WHEN OTHERS — a logging
--      failure can never block the user's save.
--   5. Forward-compatible with decision E8: the trigger reads NEW.source if
--      the column exists (via to_jsonb), else falls back to 'manual'.
--
-- ANALYTICS QUERY
--   SELECT * FROM public.saves_per_user_7d;
--   -- Returns: active_users, median, p10, p90 over rolling 7d window.
--
-- ROLLBACK
--   DROP TRIGGER IF EXISTS on_spot_list_item_inserted_emit_save_event ON public.spot_list_items;
--   DROP FUNCTION IF EXISTS public.emit_save_event();
--   DROP VIEW IF EXISTS public.saves_per_user_7d;
--   DROP TABLE IF EXISTS public.save_events;

-- ============================================
-- Step 1: Table
-- ============================================
CREATE TABLE IF NOT EXISTS public.save_events (
  id          BIGSERIAL PRIMARY KEY,
  user_id     UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  spot_id     TEXT,
  list_id     UUID,
  source      TEXT        NOT NULL DEFAULT 'manual',
  occurred_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.save_events IS
  'One row per save (insert into spot_list_items). Forward-only event log for Phase 2 readiness metrics. Source of truth is spot_list_items; this table is observability.';

CREATE INDEX IF NOT EXISTS save_events_user_occurred_idx
  ON public.save_events (user_id, occurred_at DESC);

CREATE INDEX IF NOT EXISTS save_events_occurred_idx
  ON public.save_events (occurred_at DESC);

-- ============================================
-- Step 2: RLS
-- ============================================
ALTER TABLE public.save_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Save events: owner reads" ON public.save_events;
CREATE POLICY "Save events: owner reads"
  ON public.save_events
  FOR SELECT
  USING (auth.uid() = user_id);

-- No INSERT/UPDATE/DELETE policies. Writes only via the SECURITY DEFINER
-- trigger below; analytics reads use the service role (which bypasses RLS).

-- ============================================
-- Step 3: Emission trigger
-- ============================================
CREATE OR REPLACE FUNCTION public.emit_save_event()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_source  TEXT;
BEGIN
  -- Resolve the owning user from the list.
  SELECT ul.user_id
    INTO v_user_id
    FROM public.user_lists ul
   WHERE ul.id = NEW.list_id;

  IF v_user_id IS NULL THEN
    -- Orphaned list_id — log and bail. Don't block the underlying insert.
    RAISE WARNING 'emit_save_event: could not resolve user_id for list_id=%', NEW.list_id;
    RETURN NEW;
  END IF;

  -- Forward-compat with decision E8: read NEW.source if the column exists,
  -- otherwise default to 'manual'. Using to_jsonb sidesteps a hard column
  -- reference so this trigger still compiles before E8's migration lands.
  v_source := COALESCE(to_jsonb(NEW) ->> 'source', 'manual');

  BEGIN
    INSERT INTO public.save_events (user_id, spot_id, list_id, source)
    VALUES (v_user_id, NEW.spot_id, NEW.list_id, v_source);
  EXCEPTION WHEN OTHERS THEN
    -- Critical invariant: emission failure must never block the user's save.
    RAISE WARNING 'emit_save_event: insert failed for user_id=% spot_id=% list_id=%: %',
      v_user_id, NEW.spot_id, NEW.list_id, SQLERRM;
  END;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.emit_save_event IS
  'AFTER INSERT trigger on spot_list_items. Emits one save_events row per save. Failure-isolated: any exception is logged as a WARNING; the underlying spot_list_items insert always succeeds.';

DROP TRIGGER IF EXISTS on_spot_list_item_inserted_emit_save_event ON public.spot_list_items;
CREATE TRIGGER on_spot_list_item_inserted_emit_save_event
  AFTER INSERT ON public.spot_list_items
  FOR EACH ROW
  EXECUTE FUNCTION public.emit_save_event();

-- ============================================
-- Step 4: Aggregation view
-- ============================================
-- Rolling 7-day saves per user, summarized.
-- NOTE: percentile_cont returns NULL when the input set is empty (no users
-- have saved in the last 7 days). Callers must handle nullable aggregates.
CREATE OR REPLACE VIEW public.saves_per_user_7d AS
WITH per_user AS (
  SELECT user_id, COUNT(*)::int AS saves_7d
    FROM public.save_events
   WHERE occurred_at > now() - INTERVAL '7 days'
   GROUP BY user_id
)
SELECT
  COUNT(*)::int                                                       AS active_users,
  percentile_cont(0.5)  WITHIN GROUP (ORDER BY saves_7d)::numeric     AS median,
  percentile_cont(0.10) WITHIN GROUP (ORDER BY saves_7d)::numeric     AS p10,
  percentile_cont(0.90) WITHIN GROUP (ORDER BY saves_7d)::numeric     AS p90
FROM per_user;

COMMENT ON VIEW public.saves_per_user_7d IS
  'Rolling 7d saves-per-user aggregates (median, p10, p90). Used to evaluate the Phase 2 readiness gate (avg 20+ saves/user).';

-- ============================================
-- Step 5: Sanity checks (run manually after applying)
-- ============================================
-- 1. Save a spot in the app, then:
--      SELECT * FROM public.save_events
--       WHERE user_id = auth.uid()
--       ORDER BY occurred_at DESC LIMIT 5;
--    Expected: 1 row with source = 'manual', spot_id + list_id populated.
--
-- 2. Aggregate view:
--      SELECT * FROM public.saves_per_user_7d;
--    Expected: active_users >= 1, median/p10/p90 non-null once any user has
--    saved in the last 7 days.
--
-- 3. Failure isolation: temporarily DROP the save_events table, save a spot
--    in the app — the save still succeeds (trigger swallows the error).
--    Restore by re-running this migration.
