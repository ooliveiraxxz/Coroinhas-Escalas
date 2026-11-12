-- All time-bound notices must be closed or expired before being archived by a recipient.
CREATE OR REPLACE FUNCTION public.archive_my_notification(p_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_user uuid := auth.uid(); v_count integer;v_notification public.notifications%rowtype;
BEGIN
 IF v_user IS NULL OR NOT public.is_approved() THEN
  RAISE EXCEPTION 'Acesso não autorizado' USING ERRCODE='42501';
 END IF;
 IF p_id IS NULL THEN RAISE EXCEPTION 'Notificação inválida' USING ERRCODE='22023'; END IF;
 SELECT * INTO v_notification FROM public.notifications WHERE id=p_id AND user_id=v_user;
 IF NOT FOUND THEN RETURN false; END IF;
 IF v_notification.priority_until>now() THEN RAISE EXCEPTION 'Aguarde o encerramento do prazo desta notificação' USING ERRCODE='22023'; END IF;
 IF v_notification.event_key='polls' AND v_notification.group_id IS NOT NULL AND EXISTS(SELECT 1 FROM public.polls WHERE id=v_notification.group_id AND ends_at>now() AND closed_at IS NULL AND archived_at IS NULL) THEN RAISE EXCEPTION 'Aguarde o encerramento da enquete para apagar' USING ERRCODE='22023'; END IF;
 IF v_notification.event_key='open_questions' AND v_notification.group_id IS NOT NULL AND EXISTS(SELECT 1 FROM public.open_questions WHERE id=v_notification.group_id AND ends_at>now() AND archived_at IS NULL) THEN RAISE EXCEPTION 'Aguarde o encerramento da pergunta para apagar' USING ERRCODE='22023'; END IF;
 UPDATE public.notifications
 SET archived_at=now()
 WHERE id=p_id AND user_id=v_user AND archived_at IS NULL;
 GET DIAGNOSTICS v_count=ROW_COUNT;
 RETURN v_count=1;
END
$function$
;
