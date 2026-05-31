-- ============================================
-- PR-B: default lists land at visibility='followers' on user signup
-- ============================================
-- The v4 visibility rename migration (20260101005000) backfilled EXISTING
-- default lists from 'private' to 'followers'. This migration handles
-- FUTURE inserts: the create_default_lists_for_user function (called via
-- on_auth_user_created_create_lists trigger at signup) needs to set
-- visibility='followers' explicitly, otherwise new default lists land at
-- the column DEFAULT ('private') and break the per-user social wedge
-- promise (§3.2 in the plan).
--
-- Function body is otherwise identical to extend_guard_create_default_lists_rpc.sql:
-- same guards, same kind values, same ON CONFLICT handling. Only the
-- VALUES tuples gain an explicit visibility column.

CREATE OR REPLACE FUNCTION public.create_default_lists_for_user(p_user_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Block anonymous Supabase clients outright.
  IF auth.role() = 'anon' THEN
    RAISE EXCEPTION 'unauthorized: anonymous callers may not provision default lists';
  END IF;

  -- Authenticated callers must be acting on their own row. Trigger and
  -- service-role callers (auth.role() in 'service_role','postgres', or
  -- NULL for trigger context) bypass this check intentionally.
  IF auth.role() = 'authenticated' AND auth.uid() IS DISTINCT FROM p_user_id THEN
    RAISE EXCEPTION 'unauthorized: cannot create default lists for another user';
  END IF;

  -- Insert the 3 default lists at visibility='followers' (PR-B / D6 / §3.2).
  -- Custom lists keep the column default ('private') — they're created
  -- via the New List UI which carries its own visibility radio.
  INSERT INTO public.user_lists (user_id, kind, name, visibility)
  VALUES
    (p_user_id, 'favorites'::public.list_kind_enum,  NULL, 'followers'::public.list_visibility_enum),
    (p_user_id, 'liked'::public.list_kind_enum,      NULL, 'followers'::public.list_visibility_enum),
    (p_user_id, 'want_to_go'::public.list_kind_enum, NULL, 'followers'::public.list_visibility_enum)
  ON CONFLICT (user_id, kind)
    WHERE kind IN ('favorites', 'liked', 'want_to_go')
    DO NOTHING;
END;
$$;

COMMENT ON FUNCTION public.create_default_lists_for_user IS
  'Creates the 3 default lists (Favorites/Liked/Want to Go) for a user '
  'at visibility=''followers'' (PR-B / D6 / §3.2). Guarded so anon callers '
  'are blocked and authenticated callers can only act on their own user_id; '
  'trigger/service-role contexts are allowed.';
