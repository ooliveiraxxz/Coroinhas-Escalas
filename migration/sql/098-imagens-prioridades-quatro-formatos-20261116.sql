-- Migração QA: fotos em mensagens e pop-ups e prioridade nas quatro publicações.
-- Nunca aplicar no oficial sem autorização específica.
BEGIN;
ALTER TABLE public.notifications ADD COLUMN IF NOT EXISTS image_url text;
ALTER TABLE public.screen_announcements ADD COLUMN IF NOT EXISTS priority boolean NOT NULL DEFAULT false;
ALTER TABLE public.screen_announcements DROP CONSTRAINT IF EXISTS screen_announcements_target_role_check;
ALTER TABLE public.screen_announcements ADD CONSTRAINT screen_announcements_target_role_check CHECK (target_role IN ('all','coroinha','cerimoniario','pai','coordenadora','desenvolvedor','individual'));
ALTER TABLE public.screen_announcements ADD COLUMN IF NOT EXISTS priority_until timestamptz;
ALTER TABLE public.open_questions ADD COLUMN IF NOT EXISTS priority boolean NOT NULL DEFAULT false;

CREATE OR REPLACE FUNCTION public.send_notification_with_image(p_title text, p_body text, p_target text, p_recipient uuid, p_priority boolean, p_priority_until timestamp with time zone, p_image text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_group uuid;
BEGIN
 IF NOT public.has_site_permission('send_notifications') THEN RAISE EXCEPTION 'Acesso negado' USING ERRCODE='42501'; END IF;
 IF p_image IS NOT NULL AND (length(p_image)>260000 OR p_image !~ '^data:image/(jpeg|png|webp);base64,[A-Za-z0-9+/=]+$') THEN
   RAISE EXCEPTION 'Imagem inválida ou muito grande' USING ERRCODE='22023'; END IF;
 v_group:=public.send_notification_prioritized(p_title,p_body,p_target,p_recipient,p_priority,p_priority_until);
 IF p_image IS NOT NULL AND p_image<>'' THEN UPDATE public.notifications SET image_url=p_image WHERE group_id=v_group; END IF;
 RETURN v_group;
END $function$

;
CREATE OR REPLACE FUNCTION public.open_question_create_priority(p_question text, p_target text, p_ends_at timestamp with time zone, p_priority boolean)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_question uuid;
BEGIN
 IF NOT public.has_site_permission('manage_polls') THEN RAISE EXCEPTION 'Acesso negado' USING ERRCODE='42501'; END IF;
 v_question:=public.open_question_create(p_question,p_target,p_ends_at);
 IF coalesce(p_priority,false) THEN
   UPDATE public.open_questions SET priority=true WHERE id=v_question;
   UPDATE public.notifications SET priority=true,priority_until=p_ends_at WHERE group_id=v_question AND event_key='open_questions';
 END IF;
 RETURN v_question;
END $function$
;

CREATE OR REPLACE FUNCTION public.publish_screen_announcement(p_title text, p_body text, p_image text, p_target text, p_target_user uuid, p_display_mode text, p_priority boolean, p_priority_until timestamp with time zone)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_id uuid; v_user uuid:=auth.uid();v_count integer;
BEGIN
 IF NOT public.has_site_permission('send_popup') THEN RAISE EXCEPTION 'Acesso negado' USING ERRCODE='42501'; END IF;
 IF length(trim(coalesce(p_title,'')))=0 AND length(trim(coalesce(p_body,'')))=0 AND length(coalesce(p_image,''))=0 THEN
 RAISE EXCEPTION 'Adicione uma mensagem ou imagem' USING ERRCODE='22023'; END IF;
 IF p_image IS NOT NULL AND p_image<>'' AND (length(p_image)>250000 OR p_image !~ '^data:image/jpeg;base64,[A-Za-z0-9+/=]+$') THEN
 RAISE EXCEPTION 'Imagem inválida ou muito grande' USING ERRCODE='22023'; END IF;
 IF p_target NOT IN ('all','coroinha','cerimoniario','pai','coordenadora','desenvolvedor','individual') OR p_target IS NULL THEN RAISE EXCEPTION 'Público inválido' USING ERRCODE='22023'; END IF;
 IF p_display_mode NOT IN ('optional','once','always') OR p_display_mode IS NULL THEN RAISE EXCEPTION 'Modo inválido' USING ERRCODE='22023'; END IF;
 IF (p_target='individual' AND p_target_user IS NULL) OR (p_target<>'individual' AND p_target_user IS NOT NULL) THEN RAISE EXCEPTION 'Destinatário inválido' USING ERRCODE='22023'; END IF;
 IF coalesce(p_priority,false) AND (p_priority_until IS NULL OR p_priority_until<=now()) THEN RAISE EXCEPTION 'Informe prazo futuro para prioridade' USING ERRCODE='22023'; END IF;
 INSERT INTO public.screen_announcements(title,body,image_url,target_role,target_user_id,display_mode,created_by,priority,priority_until)
 VALUES(coalesce(p_title,''),coalesce(p_body,''),nullif(p_image,''),p_target,p_target_user,p_display_mode,v_user,coalesce(p_priority,false),CASE WHEN p_priority THEN p_priority_until ELSE NULL END)
 RETURNING id INTO v_id;
 IF coalesce(p_priority,false) THEN
   INSERT INTO public.notifications(user_id,title,body,event_key,group_id,priority,priority_until,image_url)
   SELECT p.id,coalesce(nullif(trim(p_title),''),'Novo aviso na tela'),
     coalesce(nullif(trim(p_body),''),'Abra o aplicativo para visualizar o aviso.'),
     'screen_popup',v_id,true,p_priority_until,nullif(p_image,'')
   FROM public.profiles p WHERE p.approved AND
   (p_target='all' OR (p_target='individual' AND p.id=p_target_user) OR p.role=p_target);
   GET DIAGNOSTICS v_count=ROW_COUNT;
   IF v_count=0 THEN RAISE EXCEPTION 'Nenhum destinatário aprovado' USING ERRCODE='22023'; END IF;
 END IF;
 RETURN v_id;
END $function$

;
REVOKE ALL ON FUNCTION public.send_notification_with_image(text,text,text,uuid,boolean,timestamptz,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.open_question_create_priority(text,text,timestamptz,boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.publish_screen_announcement(text,text,text,text,uuid,text,boolean,timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.send_notification_with_image(text,text,text,uuid,boolean,timestamptz,text) TO coroinhas_app;
GRANT EXECUTE ON FUNCTION public.open_question_create_priority(text,text,timestamptz,boolean) TO coroinhas_app;
GRANT EXECUTE ON FUNCTION public.publish_screen_announcement(text,text,text,text,uuid,text,boolean,timestamptz) TO coroinhas_app;
COMMIT;