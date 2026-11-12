-- Campaign deadlines, creator ownership and archival retention instead of hard deletion.
ALTER TABLE public.notifications ADD COLUMN IF NOT EXISTS created_by uuid;

CREATE OR REPLACE FUNCTION public.send_notification_targeted(p_title text, p_body text, p_target text, p_recipient uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
 v_group uuid := gen_random_uuid();
 v_count integer;
BEGIN
 IF NOT public.has_site_permission('send_notifications') THEN RAISE EXCEPTION 'Sem permissão para esta ação' USING ERRCODE='42501'; END IF;

 -- Access controlled by has_site_permission at function entry.
 IF length(trim(coalesce(p_title,'')))=0 OR length(trim(coalesce(p_body,'')))=0 THEN
  RAISE EXCEPTION 'Informe título e mensagem' USING ERRCODE='22023';
 END IF;
 IF p_target NOT IN ('coroinha','cerimoniario','pai','coordenadora','todos','individual') OR p_target IS NULL THEN
  RAISE EXCEPTION 'Destinatário inválido' USING ERRCODE='22023';
 END IF;
 IF (p_target='individual' AND p_recipient IS NULL) OR (p_target<>'individual' AND p_recipient IS NOT NULL) THEN
  RAISE EXCEPTION 'Seleção de destinatários inválida' USING ERRCODE='22023';
 END IF;
 INSERT INTO public.notifications(user_id,title,body,group_id,seen,read_at,event_key,created_by)
 SELECT p.id, trim(p_title), trim(p_body), v_group, false, NULL,
 CASE WHEN p_target='individual' THEN 'direct_message' ELSE 'general' END, auth.uid()
 FROM public.profiles p
 WHERE p.approved = true
 AND (
  p_target='todos'
  OR (p_target='individual' AND p.id=p_recipient)
  OR (p_target IN ('coroinha','cerimoniario','pai','coordenadora') AND p.role=p_target)
 );
 GET DIAGNOSTICS v_count = ROW_COUNT;
 IF v_count=0 THEN RAISE EXCEPTION 'Nenhum destinatário aprovado encontrado para o grupo selecionado.' USING ERRCODE='P0001'; END IF;
 RETURN v_group;
END
$function$
;

CREATE OR REPLACE FUNCTION public.end_notification_campaign(p_group uuid) RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $fn$
DECLARE v_count int;
BEGIN
 IF NOT public.has_site_permission('send_notifications') THEN RAISE EXCEPTION 'Sem permissão' USING ERRCODE='42501'; END IF;
 IF EXISTS(SELECT 1 FROM public.notifications n WHERE n.group_id=p_group AND n.event_key NOT IN ('general','direct_message')) THEN RAISE EXCEPTION 'Grupo de outro tipo de aviso' USING ERRCODE='42501'; END IF;
 IF EXISTS(SELECT 1 FROM public.notifications n WHERE n.group_id=p_group AND n.created_by IS NOT NULL AND n.created_by<>auth.uid() AND NOT public.is_developer()) THEN RAISE EXCEPTION 'Esta notificação pertence a outra pessoa' USING ERRCODE='42501'; END IF;
 UPDATE public.notifications SET priority_until=now(),priority=false
 WHERE group_id=p_group AND event_key IN ('general','direct_message') AND priority_until>now() AND archived_at IS NULL;
 GET DIAGNOSTICS v_count=ROW_COUNT;RETURN v_count>0;
END $fn$;

CREATE OR REPLACE FUNCTION public.delete_notification(p_group uuid) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $fn$
BEGIN
 IF NOT public.has_site_permission('send_notifications') THEN RAISE EXCEPTION 'Acesso negado' USING ERRCODE='42501'; END IF;
 IF EXISTS(SELECT 1 FROM public.notifications WHERE group_id=p_group AND event_key NOT IN ('general','direct_message')) THEN RAISE EXCEPTION 'Este conteúdo deve ser gerenciado na área de enquetes ou perguntas' USING ERRCODE='42501'; END IF;
 IF EXISTS(SELECT 1 FROM public.notifications WHERE group_id=p_group AND created_by IS NOT NULL AND created_by<>auth.uid() AND NOT public.is_developer()) THEN RAISE EXCEPTION 'Esta notificação pertence a outra pessoa' USING ERRCODE='42501'; END IF;
 IF EXISTS(SELECT 1 FROM public.notifications WHERE group_id=p_group AND priority_until>now() AND archived_at IS NULL) THEN RAISE EXCEPTION 'Encerre o prazo desta mensagem antes de apagá-la' USING ERRCODE='22023'; END IF;
 UPDATE public.notifications SET archived_at=now() WHERE group_id=p_group AND event_key IN ('general','direct_message') AND archived_at IS NULL;
END $fn$;

REVOKE ALL ON FUNCTION public.end_notification_campaign(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.end_notification_campaign(uuid) TO coroinhas_app;
