-- Reduce directly granted privileges not backed by RLS policies.
-- Excludes tables whose writes are intentional in current app.
DO $g$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM migration_private.environment WHERE id=true
  AND branch_id IN('br-rough-hill-bcj6lzt1','br-odd-bread-bc1jxzsh'))
 THEN RAISE EXCEPTION 'Wrong branch' USING ERRCODE='42501'; END IF;
END $g$;
-- Initial profiles come only from migration_private.resolve_neon_identity
-- (SECURITY DEFINER), not direct client SQL.
REVOKE INSERT,DELETE ON public.profiles FROM coroinhas_app;
-- Notifications are deleted/marked through controlled RPCs, not open SQL.
REVOKE DELETE ON public.notifications FROM coroinhas_app;
-- Approved users can send messages, but not edit/delete others' messages.
REVOKE UPDATE,DELETE ON public.messages FROM coroinhas_app;
-- Requests are inserted by coroinhas and updated by coordinators; no
-- direct deletion policy exists.
REVOKE DELETE ON public.requests FROM coroinhas_app;
