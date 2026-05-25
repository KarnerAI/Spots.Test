-- Updates create_lists_for_existing_users for the Phase 1 `kind` rename.
--
-- This is a one-time migration helper from create_location_saving_schema.sql
-- (lines 367-393) that backfilled default lists for users who signed up
-- before the lists feature shipped. After the 2026-05-23_phase1_lists_and_-
-- imports.sql migration drops `user_lists.list_type`, the existing function
-- body still references that column and would error if anyone ever called
-- it again. Update it to use `kind` for DB consistency, even though it's
-- vanishingly unlikely to ever be called again post-Phase-1.
--
-- Run order: apply AFTER 2026-05-23_phase1_lists_and_imports.sql and AFTER
-- extend_guard_create_default_lists_rpc.sql (this calls
-- create_default_lists_for_user which must already be updated).

CREATE OR REPLACE FUNCTION public.create_lists_for_existing_users()
RETURNS TABLE(created_count INTEGER)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  user_record RECORD;
  lists_created INTEGER := 0;
BEGIN
  -- For each user who doesn't have all 3 default lists, create them.
  -- Post-Phase-1 the kind enum values are favorites/liked/want_to_go
  -- (replaces the legacy starred/favorites/bucket_list list_type values).
  FOR user_record IN
    SELECT DISTINCT u.id
    FROM auth.users u
    WHERE NOT EXISTS (
      SELECT 1 FROM public.user_lists ul
      WHERE ul.user_id = u.id
        AND ul.kind IN ('favorites', 'liked', 'want_to_go')
      GROUP BY ul.user_id
      HAVING COUNT(DISTINCT ul.kind) = 3
    )
  LOOP
    PERFORM public.create_default_lists_for_user(user_record.id);
    lists_created := lists_created + 1;
  END LOOP;

  RETURN QUERY SELECT lists_created;
END;
$$;

COMMENT ON FUNCTION public.create_lists_for_existing_users IS
  'One-shot migration helper. Creates the 3 default lists (favorites / '
  'liked / want_to_go) for any user who is missing one or more. Idempotent. '
  'Almost certainly never needs to run post Phase 1 — kept consistent with '
  'the new kind enum so the function isnt broken if someone ever does call it.';
