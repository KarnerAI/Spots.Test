-- ============================================
-- Onboarding telemetry events
-- ============================================
-- Run in Supabase Dashboard → Database → SQL Editor.
-- Idempotent and reversible.
--
-- PURPOSE
-- Per-step instrumentation for the post-signup onboarding flow.
-- Without this we ship v1 blind to which screens leak users.
-- Captures four event types:
--
--   step_completed       — user tapped Continue on screen N
--   step_skipped         — user tapped Skip on screen N
--   step_revisited       — user back-navigated to screen N (the FURTHEST
--                          step in profiles.onboarding_step is unchanged;
--                          this event provides separate observability)
--   onboarding_completed — user tapped Done on screen 4
--                          (or finished via Skip on screen 4)
--
-- The iOS client writes one row per event via
-- `ProfileService.logOnboardingEvent(_:step:)`. Writes are
-- fire-and-forget — if the request fails the user-visible state
-- machine is not blocked (the step transition in `profiles.onboarding_step`
-- is the source of truth; this table is observability).
--
-- ANALYTICS QUERY EXAMPLES
--   -- Funnel completion rate per step (last 30 days):
--   SELECT step,
--          COUNT(*) FILTER (WHERE event_type = 'step_completed') AS completed,
--          COUNT(*) FILTER (WHERE event_type = 'step_skipped')   AS skipped,
--          COUNT(*) FILTER (WHERE event_type = 'step_revisited') AS revisited
--     FROM public.onboarding_events
--    WHERE occurred_at > now() - INTERVAL '30 days'
--    GROUP BY step
--    ORDER BY step;
--
--   -- Median time to complete onboarding:
--   SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY duration_s) AS median_seconds
--     FROM (
--       SELECT user_id,
--              EXTRACT(EPOCH FROM (MAX(occurred_at) - MIN(occurred_at))) AS duration_s
--         FROM public.onboarding_events
--        GROUP BY user_id
--        HAVING bool_or(event_type = 'onboarding_completed')
--     ) AS per_user;
--
-- ROLLBACK
--   DROP TABLE IF EXISTS public.onboarding_events;

-- ============================================
-- Step 1: Table
-- ============================================
CREATE TABLE IF NOT EXISTS public.onboarding_events (
  id          BIGSERIAL PRIMARY KEY,
  user_id     UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  event_type  TEXT        NOT NULL,
  step        SMALLINT,
  occurred_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT onboarding_events_type_check CHECK (
    event_type IN ('step_completed', 'step_skipped', 'step_revisited', 'onboarding_completed')
  ),

  -- step is required for everything except onboarding_completed (which
  -- is a flow-level event, not screen-level).
  CONSTRAINT onboarding_events_step_check CHECK (
    (event_type = 'onboarding_completed' AND step IS NULL)
    OR
    (event_type <> 'onboarding_completed' AND step BETWEEN 1 AND 4)
  )
);

COMMENT ON TABLE public.onboarding_events IS
  'Per-step onboarding telemetry. Source of truth: this is observability data, not state. The user-facing state machine reads profiles.onboarding_step.';

-- ============================================
-- Step 2: Indexes
-- ============================================
-- Per-user funnel queries ("show me a user''s onboarding journey").
CREATE INDEX IF NOT EXISTS onboarding_events_user_occurred_idx
  ON public.onboarding_events (user_id, occurred_at);

-- Aggregate analytics ("what % of users skip step 3?").
CREATE INDEX IF NOT EXISTS onboarding_events_type_step_idx
  ON public.onboarding_events (event_type, step);

-- ============================================
-- Step 3: Row Level Security
-- ============================================
ALTER TABLE public.onboarding_events ENABLE ROW LEVEL SECURITY;

-- Users can insert their own events (the only write path; the iOS
-- client writes these as part of the onboarding flow).
DROP POLICY IF EXISTS "Onboarding events: owner inserts" ON public.onboarding_events;
CREATE POLICY "Onboarding events: owner inserts"
  ON public.onboarding_events
  FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- Users can read their own events. Service role (analytics) reads
-- everything via Supabase's built-in service-role bypass — no policy
-- needed for that path.
DROP POLICY IF EXISTS "Onboarding events: owner reads" ON public.onboarding_events;
CREATE POLICY "Onboarding events: owner reads"
  ON public.onboarding_events
  FOR SELECT
  USING (auth.uid() = user_id);

-- No UPDATE or DELETE policies: events are immutable from the client.
-- If you need to delete them, do it as service role.

-- ============================================
-- Step 4: Sanity check after running
-- ============================================
-- After your next onboarding test run (a new account stepping through):
--   SELECT event_type, step, occurred_at
--     FROM public.onboarding_events
--    WHERE user_id = auth.uid()
--    ORDER BY occurred_at;
-- Expected: chronological list of step_completed / step_skipped /
-- step_revisited rows, ending in onboarding_completed.
