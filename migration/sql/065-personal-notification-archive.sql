-- User-owned notification archive: hide immediately, purge through existing 30-day archive retention.
CREATE OR REPLACE FUNCTION public.archive_my_notification(p_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE v_user uuid := auth.uid(); v_count integer;
BEGIN
 IF v_user IS NULL OR NOT public.is_approved() THEN
  RAISE EXCEPTION 'Acesso não autorizado' USING ERRCODE='42501';
 END IF;
 IF p_id IS NULL THEN RAISE EXCEPTION 'Notificação inválida' USING ERRCODE='22023'; END IF;
 UPDATE public.notifications
 SET archived_at=now()
 WHERE id=p_id AND user_id=v_user AND archived_at IS NULL;
 GET DIAGNOSTICS v_count=ROW_COUNT;
 RETURN v_count=1;
END
$function$;

REVOKE ALL ON FUNCTION public.archive_my_notification(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.archive_my_notification(uuid) TO coroinhas_app;
