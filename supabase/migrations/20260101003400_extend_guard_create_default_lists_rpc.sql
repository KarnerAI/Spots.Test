-- Extends create_default_lists_for_user to set `kind` on the 3 default
-- system lists (decision E7).
--
-- This replaces the function body in guard_create_default_lists_rpc.sql,
-- which inserted the rows using the legacy `list_type` enum. After the
-- 2026-05-23_phase1_lists_and_imports.sql migration drops `list_type`
-- and introduces `list_kind_enum`, the function must insert using `kind`
-- instead.
--
-- Mapping carried over from the migration's backfill:
--   list_type = 'starred'     -> kind = 'favorites'    ("Favorites")
--   list_type = 'favorites'   -> kind = 'liked'        ("Liked")
--   list_type = 'bucket_list' -> kind = 'want_to_go'   ("Want to Go")
--
-- The guard logic (anon-block + cross-user block) is preserved
-- byte-for-byte from guard_create_default_lists_rpc.sql.
--
-- Run order: apply AFTER 2026-05-23_phase1_lists_and_imports.sql.

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

  -- Insert the 3 default lists if they don't exist. The partial unique
  -- index user_lists_unique_system_kind_idx
  -- ON (user_id, kind) WHERE kind IN ('favorites','liked','want_to_go')
  -- enforces one-of-each per user; ON CONFLICT targets it.
  INSERT INTO public.user_lists (user_id, kind, name)
  VALUES
    (p_user_id, 'favorites'::public.list_kind_enum,  NULL),
    (p_user_id, 'liked'::public.list_kind_enum,      NULL),
    (p_user_id, 'want_to_go'::public.list_kind_enum, NULL)
  ON CONFLICT (user_id, kind)
    WHERE kind IN ('favorites', 'liked', 'want_to_go')
    DO NOTHING;
END;
$$;

COMMENT ON FUNCTION public.create_default_lists_for_user IS
  'Creates the 3 default lists (Favorites/Liked/Want to Go, keyed by '
  'kind enum) for a user. Guarded so anon callers are blocked and '
  'authenticated callers can only act on their own user_id; '
  'trigger/service-role contexts are allowed.';
