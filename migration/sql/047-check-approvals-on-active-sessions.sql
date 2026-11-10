-- Periodically check pending three-hour approvals when approved users are online.
-- A separate scheduler is still needed to guarantee execution while the site has no active users.
CREATE OR REPLACE FUNCTION public.poll_tick()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_poll jsonb; v_approved int;
BEGIN
 IF auth.uid() IS NULL OR NOT public.is_approved() THEN
  RAISE EXCEPTION 'Acesso não autorizado' USING ERRCODE='42501';
 END IF;
 v_poll:=public.poll_dispatch();
 v_approved:=public.run_pending_auto_approvals();
 RETURN v_poll||jsonb_build_object('autoApprovals',v_approved);
END $function$;
