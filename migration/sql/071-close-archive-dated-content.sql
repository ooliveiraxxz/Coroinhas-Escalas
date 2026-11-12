-- Lifecycle controls for dated content, linked notifications and access restrictions.
CREATE OR REPLACE FUNCTION public.open_question_close(p_question uuid) RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $fn$
DECLARE n integer;BEGIN
 IF NOT public.has_site_permission('manage_polls') THEN RAISE EXCEPTION 'Sem permissão' USING ERRCODE='42501'; END IF;
 UPDATE public.open_questions SET ends_at=now() WHERE id=p_question AND ends_at>now() AND archived_at IS NULL AND (created_by=auth.uid() OR public.is_developer());
 GET DIAGNOSTICS n=ROW_COUNT;RETURN n=1;
END $fn$;

CREATE OR REPLACE FUNCTION public.open_question_archive(p_question uuid) RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $fn$
DECLARE n integer;BEGIN
 IF NOT public.has_site_permission('manage_polls') THEN RAISE EXCEPTION 'Sem permissão' USING ERRCODE='42501'; END IF;
 IF EXISTS(SELECT 1 FROM public.open_questions WHERE id=p_question AND ends_at>now() AND archived_at IS NULL AND (created_by=auth.uid() OR public.is_developer())) THEN RAISE EXCEPTION 'Encerre a pergunta antes de apagá-la' USING ERRCODE='22023'; END IF;
 UPDATE public.open_questions SET archived_at=now() WHERE id=p_question AND ends_at<=now() AND archived_at IS NULL AND (created_by=auth.uid() OR public.is_developer());
 GET DIAGNOSTICS n=ROW_COUNT;RETURN n=1;
END $fn$;

CREATE OR REPLACE FUNCTION public.poll_close(p_poll uuid) RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $fn$
DECLARE n integer;BEGIN
 IF NOT public.has_site_permission('manage_polls') THEN RAISE EXCEPTION 'Sem permissão' USING ERRCODE='42501'; END IF;
 UPDATE public.polls SET ends_at=now() WHERE id=p_poll AND ends_at>now() AND archived_at IS NULL AND (created_by=auth.uid() OR public.is_developer());
 GET DIAGNOSTICS n=ROW_COUNT;RETURN n=1;
END $fn$;

CREATE OR REPLACE FUNCTION public.poll_archive(p_poll uuid) RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $fn$
DECLARE n integer;BEGIN
 IF NOT public.has_site_permission('manage_polls') THEN RAISE EXCEPTION 'Sem permissão' USING ERRCODE='42501'; END IF;
 IF EXISTS(SELECT 1 FROM public.polls WHERE id=p_poll AND ends_at>now() AND archived_at IS NULL AND (created_by=auth.uid() OR public.is_developer())) THEN RAISE EXCEPTION 'Encerre a enquete antes de apagá-la' USING ERRCODE='22023'; END IF;
 UPDATE public.polls SET archived_at=now() WHERE id=p_poll AND ends_at<=now() AND archived_at IS NULL AND (created_by=auth.uid() OR public.is_developer());
 GET DIAGNOSTICS n=ROW_COUNT;RETURN n=1;
END $fn$;

CREATE OR REPLACE FUNCTION public.poll_list()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_user uuid:=auth.uid();v_coord boolean;
BEGIN
 IF v_user IS NULL OR NOT public.is_approved() THEN RAISE EXCEPTION 'Acesso não autorizado' USING ERRCODE='42501'; END IF;
 v_coord:=public.has_site_permission('manage_polls');
 RETURN coalesce((
  SELECT jsonb_agg(jsonb_build_object(
    'id',p.id,'created_by',p.created_by,'question',CASE WHEN v_coord OR now()<p.ends_at THEN p.question ELSE 'Enquete encerrada' END,
    'starts_at',p.starts_at,'ends_at',p.ends_at,
    'multiple_answers',CASE WHEN v_coord OR now()<p.ends_at THEN p.multiple_answers ELSE false END,
    'priority',p.priority,
    'state',CASE WHEN now()<p.starts_at THEN 'agendada' WHEN now()>=p.ends_at THEN 'encerrada' ELSE 'aberta' END,
    'voted',EXISTS(SELECT 1 FROM public.poll_votes v WHERE v.poll_id=p.id AND v.user_id=v_user),
    'my_options',CASE WHEN r.role='coroinha' AND now()>=p.starts_at AND now()<p.ends_at
       THEN (SELECT coalesce(jsonb_agg(v.option_id ORDER BY o.position),'[]'::jsonb)
        FROM public.poll_votes v
        JOIN public.poll_options o ON o.id=v.option_id AND o.poll_id=v.poll_id
        WHERE v.poll_id=p.id AND v.user_id=v_user)
       ELSE '[]'::jsonb END,
    'options',CASE WHEN v_coord OR (now()>=p.starts_at AND now()<p.ends_at AND r.role='coroinha')
      THEN (SELECT coalesce(jsonb_agg(jsonb_build_object('id',o.id,'label',o.label,'position',o.position) ORDER BY o.position),'[]'::jsonb)
        FROM public.poll_options o WHERE o.poll_id=p.id)
      ELSE '[]'::jsonb END,
    'results',CASE WHEN v_coord THEN (SELECT coalesce(jsonb_agg(jsonb_build_object(
       'id',o.id,'label',o.label,
       'votes',(SELECT count(*) FROM public.poll_votes v WHERE v.poll_id=p.id AND v.option_id=o.id),
       'voters',(SELECT coalesce(jsonb_agg(jsonb_build_object(
        'name',coalesce(nullif(trim(pr.name),''),'Coroinha sem nome'),
        'voted_at',v.created_at
       ) ORDER BY lower(coalesce(pr.name,'')),v.created_at),'[]'::jsonb)
       FROM public.poll_votes v
       JOIN public.profiles pr ON pr.id=v.user_id
       WHERE v.poll_id=p.id AND v.option_id=o.id)
      ) ORDER BY o.position),'[]'::jsonb)
       FROM public.poll_options o WHERE o.poll_id=p.id) ELSE '[]'::jsonb END,
    'respondents',CASE WHEN v_coord THEN (SELECT count(DISTINCT v.user_id) FROM public.poll_votes v WHERE v.poll_id=p.id) ELSE NULL END
   ) ORDER BY p.created_at DESC)
  FROM public.polls p JOIN public.profiles r ON r.id=v_user
  WHERE p.archived_at IS NULL AND (v_coord OR (r.role='coroinha' AND p.starts_at<=now()))
 ),'[]'::jsonb);
END $function$
;

CREATE OR REPLACE FUNCTION public.open_question_create(p_question text, p_target text, p_ends_at timestamp with time zone)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_user uuid:=auth.uid();v_group text;v_role text;v_id uuid;
BEGIN
 IF NOT public.has_site_permission('manage_polls') THEN RAISE EXCEPTION 'Sem permissão' USING ERRCODE='42501'; END IF;
 SELECT role,coordination_group INTO v_role,v_group FROM public.profiles WHERE id=v_user AND approved;
 IF p_target NOT IN ('coroinha','cerimoniario','pai','coordenadora','todos') THEN RAISE EXCEPTION 'Público inválido' USING ERRCODE='22023'; END IF;
 IF v_role<>'desenvolvedor' AND p_target<>v_group THEN RAISE EXCEPTION 'Somente perguntas para seu grupo' USING ERRCODE='42501'; END IF;
 IF length(trim(coalesce(p_question,''))) NOT BETWEEN 5 AND 500 THEN RAISE EXCEPTION 'Escreva uma pergunta de 5 a 500 caracteres' USING ERRCODE='22023'; END IF;
 IF p_ends_at<=now() OR p_ends_at>now()+interval '90 days' THEN RAISE EXCEPTION 'Prazo inválido' USING ERRCODE='22023'; END IF;
 INSERT INTO public.open_questions(question,target_role,created_by,ends_at)
 VALUES(trim(p_question),p_target,v_user,p_ends_at) RETURNING id INTO v_id;
 INSERT INTO public.notifications(user_id,title,body,event_key,group_id)
 SELECT p.id,'Nova pergunta para responder',left(trim(p_question),400),'open_questions',v_id
 FROM public.profiles p WHERE p.approved AND p.id<>v_user
 AND (p_target='todos' OR p.role=p_target)
 AND p.role<>'desenvolvedor';
 RETURN v_id;
END $function$
;

CREATE OR REPLACE FUNCTION public.open_question_answer(p_question uuid, p_answer text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_user uuid:=auth.uid();v_role text;v_q public.open_questions%rowtype;
BEGIN
 IF v_user IS NULL OR NOT public.is_approved() THEN RAISE EXCEPTION 'Acesso negado' USING ERRCODE='42501'; END IF;
 SELECT role INTO v_role FROM public.profiles WHERE id=v_user;
 SELECT * INTO v_q FROM public.open_questions WHERE id=p_question;
 IF NOT FOUND OR v_q.archived_at IS NOT NULL OR v_q.ends_at<=now() THEN RAISE EXCEPTION 'Pergunta encerrada ou indisponível' USING ERRCODE='22023'; END IF;
 IF v_q.created_by=v_user THEN RAISE EXCEPTION 'Quem publicou não pode responder sua própria pergunta' USING ERRCODE='42501'; END IF;
 IF v_q.target_role<>'todos' AND v_q.target_role<>v_role THEN RAISE EXCEPTION 'Pergunta de outro público' USING ERRCODE='42501'; END IF;
 IF length(trim(coalesce(p_answer,''))) NOT BETWEEN 1 AND 2000 THEN RAISE EXCEPTION 'Resposta deve ter até 2000 caracteres' USING ERRCODE='22023'; END IF;
 INSERT INTO public.open_question_answers(question_id,user_id,answer) VALUES(p_question,v_user,trim(p_answer))
 ON CONFLICT(question_id,user_id) DO NOTHING;
 IF NOT FOUND THEN RAISE EXCEPTION 'Você já respondeu esta pergunta' USING ERRCODE='22023'; END IF;
 INSERT INTO public.notifications(user_id,title,body,event_key)
 VALUES(v_q.created_by,'Nova resposta recebida',left(trim(p_answer),300),'general');
 RETURN true;
END $function$
;

CREATE OR REPLACE FUNCTION public.poll_dispatch()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v public.polls%ROWTYPE; v_open int:=0;v_rem int:=0;v_closed int:=0;
BEGIN
 IF NOT public.automation_enabled('poll_dispatch') THEN RETURN jsonb_build_object('abertas',0,'lembretes',0,'encerradas',0); END IF;

 FOR v IN SELECT * FROM public.polls
  WHERE starts_at<=now() AND ends_at>now() AND started_notified_at IS NULL
  ORDER BY starts_at FOR UPDATE SKIP LOCKED LOOP
  INSERT INTO public.notifications(user_id,title,body,event_key,priority,priority_until,group_id)
  SELECT id,'Nova enquete disponível',v.question,'polls',v.priority,v.ends_at,v.id
  FROM public.profiles WHERE approved AND role='coroinha';
  UPDATE public.polls SET started_notified_at=now() WHERE id=v.id;
  v_open:=v_open+1;
 END LOOP;
 FOR v IN SELECT * FROM public.polls
  WHERE started_notified_at IS NOT NULL AND reminder_notified_at IS NULL
  AND ends_at>now() AND starts_at<=ends_at-interval '24 hours'
  AND now()>=ends_at-interval '24 hours'
  ORDER BY ends_at FOR UPDATE SKIP LOCKED LOOP
  INSERT INTO public.notifications(user_id,title,body,event_key,priority,priority_until,group_id)
  SELECT p.id,'Falta 1 dia para encerrar a enquete',v.question||' — responda antes de '||
   to_char(v.ends_at AT TIME ZONE 'America/Sao_Paulo','DD/MM "às" HH24:MI'),
   'polls',v.priority,v.ends_at,v.id
  FROM public.profiles p WHERE p.approved AND p.role='coroinha'
  AND NOT EXISTS(SELECT 1 FROM public.poll_votes x WHERE x.poll_id=v.id AND x.user_id=p.id);
  UPDATE public.polls SET reminder_notified_at=now() WHERE id=v.id;
  v_rem:=v_rem+1;
 END LOOP;
 FOR v IN SELECT * FROM public.polls
  WHERE ends_at<=now() AND closed_notified_at IS NULL
  ORDER BY ends_at FOR UPDATE SKIP LOCKED LOOP
  INSERT INTO public.notifications(user_id,title,body,event_key,group_id)
  SELECT p.id,'Enquete encerrada','O prazo da enquete foi encerrado.','polls',v.id
  FROM public.profiles p WHERE p.approved AND p.role='coroinha';
  UPDATE public.polls SET closed_notified_at=now() WHERE id=v.id;
  v_closed:=v_closed+1;
 END LOOP;
 RETURN jsonb_build_object('abertas',v_open,'lembretes',v_rem,'encerradas',v_closed);
END $function$
;

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
 IF v_notification.event_key='polls' AND v_notification.group_id IS NOT NULL AND EXISTS(SELECT 1 FROM public.polls WHERE id=v_notification.group_id AND ends_at>now() AND archived_at IS NULL) THEN RAISE EXCEPTION 'Aguarde o encerramento da enquete para apagar' USING ERRCODE='22023'; END IF;
 IF v_notification.event_key='open_questions' AND v_notification.group_id IS NOT NULL AND EXISTS(SELECT 1 FROM public.open_questions WHERE id=v_notification.group_id AND ends_at>now() AND archived_at IS NULL) THEN RAISE EXCEPTION 'Aguarde o encerramento da pergunta para apagar' USING ERRCODE='22023'; END IF;
 UPDATE public.notifications
 SET archived_at=now()
 WHERE id=p_id AND user_id=v_user AND archived_at IS NULL;
 GET DIAGNOSTICS v_count=ROW_COUNT;
 RETURN v_count=1;
END
$function$
;

REVOKE ALL ON FUNCTION public.open_question_close(uuid),public.open_question_archive(uuid),public.poll_close(uuid),public.poll_archive(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.open_question_close(uuid),public.open_question_archive(uuid),public.poll_close(uuid),public.poll_archive(uuid) TO coroinhas_app;
