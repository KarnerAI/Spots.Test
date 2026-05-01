-- Guards `create_default_lists_for_user` against unauthorized callers.
--
-- Why: the function is `SECURITY DEFINER` (bypasses RLS). Without an explicit
-- caller check it executes with table-owner privilege for any role that can
-- invoke it — including `anon`. A logged-in user could also pass another
-- user's UUID and get default lists provisioned in their name.
--
-- The function is also called from the `create_lists_for_new_user` trigger
-- (see create_location_saving_schema.sql:338-356), which runs as the postgres
-- role with no auth context. We must keep that path working, so the guard
-- only kicks in when `auth.role()` indicates an external Supabase caller.
--
-- Run order: apply AFTER create_location_saving_schema.sql.

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
  -- service-role callers (auth.role() in 'service_role','postgres', or NULL
  -- for trigger context) bypass this check intentionally.
  IF auth.role() = 'authenticated' AND auth.uid() IS DISTINCT FROM p_user_id THEN
    RAISE EXCEPTION 'unauthorized: cannot create default lists for another user';
  END IF;

  -- Insert the 3 default lists if they don't exist
  INSERT INTO public.user_lists (user_id, list_type, name)
  VALUES
    (p_user_id, 'starred', NULL),
    (p_user_id, 'favorites', NULL),
    (p_user_id, 'bucket_list', NULL)
  ON CONFLICT (user_id, list_type) DO NOTHING;
END;
$$;

COMMENT ON FUNCTION public.create_default_lists_for_user IS 'Creates the 3 default lists (Top Spots, Favorites, Want to Go) for a user. Guarded so anon callers are blocked and authenticated callers can only act on their own user_id; trigger/service-role contexts are allowed.';
