-- Preserve scheduled dates while closing polls manually; all vote, dispatch and archive paths honor closed_at.
ALTER TABLE public.polls ADD COLUMN IF NOT EXISTS closed_at timestamptz;

CREATE OR REPLACE FUNCTION public.poll_close(p_poll uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE n integer;BEGIN
 IF NOT public.has_site_permission('manage_polls') THEN RAISE EXCEPTION 'Sem permissão' USING ERRCODE='42501'; END IF;
 UPDATE public.polls SET closed_at=now() WHERE id=p_poll AND ends_at>now() AND closed_at IS NULL AND archived_at IS NULL AND (created_by=auth.uid() OR public.is_developer());
 GET DIAGNOSTICS n=ROW_COUNT;RETURN n=1;
END $function$
;

CREATE OR REPLACE FUNCTION public.poll_archive(p_poll uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE n integer;BEGIN
 IF NOT public.has_site_permission('manage_polls') THEN RAISE EXCEPTION 'Sem permissão' USING ERRCODE='42501'; END IF;
 IF EXISTS(SELECT 1 FROM public.polls WHERE id=p_poll AND ends_at>now() AND closed_at IS NULL AND archived_at IS NULL AND (created_by=auth.uid() OR public.is_developer())) THEN RAISE EXCEPTION 'Encerre a enquete antes de apagá-la' USING ERRCODE='22023'; END IF;
 UPDATE public.polls SET archived_at=now() WHERE id=p_poll AND (ends_at<=now() OR closed_at IS NOT NULL) AND archived_at IS NULL AND (created_by=auth.uid() OR public.is_developer());
 GET DIAGNOSTICS n=ROW_COUNT;RETURN n=1;
END $function$
;

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
    'state',CASE WHEN p.closed_at IS NOT NULL THEN 'encerrada' WHEN now()<p.starts_at THEN 'agendada' WHEN now()>=p.ends_at THEN 'encerrada' ELSE 'aberta' END,
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

CREATE OR REPLACE FUNCTION public.poll_vote(p_poll uuid, p_options uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_user uuid:=auth.uid();v_poll public.polls%ROWTYPE;v_count int;
BEGIN
 IF NOT public.has_site_permission('vote_polls') THEN RAISE EXCEPTION 'Sem permissão para esta ação' USING ERRCODE='42501'; END IF;

 IF v_user IS NULL OR NOT public.has_site_permission('vote_polls') THEN
  RAISE EXCEPTION 'Somente coroinhas aprovados podem responder' USING ERRCODE='42501'; END IF;
 SELECT * INTO v_poll FROM public.polls WHERE id=p_poll FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Enquete não encontrada' USING ERRCODE='22023'; END IF;
 IF now()<v_poll.starts_at THEN RAISE EXCEPTION 'A enquete ainda não começou' USING ERRCODE='22023'; END IF;
 IF v_poll.closed_at IS NOT NULL OR now()>=v_poll.ends_at THEN RAISE EXCEPTION 'Esta enquete foi encerrada' USING ERRCODE='22023'; END IF;

 v_count:=cardinality(p_options);
 IF p_options IS NULL OR v_count<1 OR v_count>10 OR (NOT v_poll.multiple_answers AND v_count<>1)
   OR v_count<>(SELECT count(DISTINCT x) FROM unnest(p_options) x)
   OR v_count<>(SELECT count(*) FROM public.poll_options WHERE poll_id=p_poll AND id=ANY(p_options)) THEN
  RAISE EXCEPTION 'Selecione uma opção válida para votar' USING ERRCODE='22023'; END IF;
 DELETE FROM public.poll_votes WHERE poll_id=p_poll AND user_id=v_user;
 INSERT INTO public.poll_votes(poll_id,option_id,user_id) SELECT p_poll,x,v_user FROM unnest(p_options) x;
 RETURN jsonb_build_object('voted',true);
END $function$
;

CREATE OR REPLACE FUNCTION public.poll_change_vote(p_poll uuid, p_options uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_user uuid:=auth.uid();v_poll public.polls%ROWTYPE;v_count integer;
BEGIN
 IF NOT public.has_site_permission('vote_polls') THEN RAISE EXCEPTION 'Sem permissão para esta ação' USING ERRCODE='42501'; END IF;

 IF v_user IS NULL OR NOT EXISTS(
  SELECT 1 FROM public.profiles WHERE id=v_user AND approved AND role='coroinha'
 ) THEN RAISE EXCEPTION 'Somente coroinhas aprovados podem responder enquetes' USING ERRCODE='42501'; END IF;
 SELECT * INTO v_poll FROM public.polls WHERE id=p_poll FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Enquete não encontrada' USING ERRCODE='22023'; END IF;
 IF now()<v_poll.starts_at THEN RAISE EXCEPTION 'Esta enquete ainda não começou' USING ERRCODE='22023'; END IF;
 IF v_poll.closed_at IS NOT NULL OR now()>=v_poll.ends_at THEN RAISE EXCEPTION 'O prazo desta enquete terminou. Não é possível modificar a resposta.' USING ERRCODE='22023'; END IF;
 v_count:=coalesce(cardinality(p_options),0);
 IF v_count<1 OR v_count>10 OR (NOT v_poll.multiple_answers AND v_count<>1)
 OR v_count<>(SELECT count(DISTINCT x) FROM unnest(p_options) AS x)
 OR v_count<>(SELECT count(*) FROM public.poll_options WHERE poll_id=p_poll AND id=ANY(p_options))
 THEN RAISE EXCEPTION 'Selecione opções válidas antes de salvar' USING ERRCODE='22023'; END IF;
 -- Only the caller's own votes are replaced; no other coroinha is modified.
 DELETE FROM public.poll_votes WHERE poll_id=p_poll AND user_id=v_user;
 INSERT INTO public.poll_votes(poll_id,option_id,user_id)
 SELECT p_poll,x,v_user FROM unnest(p_options) AS x;
 RETURN jsonb_build_object('updated',true,'count',v_count);
END $function$
;

CREATE OR REPLACE FUNCTION public.poll_update(p_poll uuid, p_question text, p_options jsonb, p_starts_at timestamp with time zone, p_ends_at timestamp with time zone, p_multiple boolean, p_priority boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_poll public.polls%ROWTYPE;v_item jsonb;v_id uuid;v_label text;v_position int:=0;v_ids uuid[]:=ARRAY[]::uuid[];v_vote_count bigint;
BEGIN
 IF NOT public.has_site_permission('manage_polls') THEN RAISE EXCEPTION 'Sem permissão para esta ação' USING ERRCODE='42501'; END IF;

 -- Access controlled by has_site_permission at function entry.
 SELECT * INTO v_poll FROM public.polls WHERE id=p_poll FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Enquete não encontrada' USING ERRCODE='22023'; END IF;
 IF v_poll.closed_at IS NOT NULL THEN RAISE EXCEPTION 'Uma enquete encerrada não pode ser editada' USING ERRCODE='22023'; END IF;
 IF char_length(trim(coalesce(p_question,''))) NOT BETWEEN 5 AND 250 THEN RAISE EXCEPTION 'Informe uma pergunta de 5 a 250 caracteres' USING ERRCODE='22023'; END IF;
 IF p_starts_at IS NULL OR p_ends_at IS NULL OR p_ends_at<=p_starts_at THEN RAISE EXCEPTION 'Datas da enquete inválidas' USING ERRCODE='22023'; END IF;
 IF jsonb_typeof(p_options)<>'array' OR jsonb_array_length(p_options) NOT BETWEEN 2 AND 10 THEN
  RAISE EXCEPTION 'Informe de 2 a 10 opções de resposta' USING ERRCODE='22023'; END IF;
 SELECT COUNT(*) INTO v_vote_count FROM public.poll_votes WHERE poll_id=p_poll;
 IF v_vote_count>0 AND p_starts_at<>v_poll.starts_at THEN
  RAISE EXCEPTION 'O início não pode mudar depois que alguém votou' USING ERRCODE='22023'; END IF;
 IF v_poll.ends_at<=now() AND p_ends_at>now() THEN
  RAISE EXCEPTION 'Uma enquete encerrada não pode ser reaberta. Crie uma nova.' USING ERRCODE='22023'; END IF;
 IF v_poll.ends_at>now() AND p_ends_at<=now() THEN
  RAISE EXCEPTION 'Para finalizar, escolha um horário futuro' USING ERRCODE='22023'; END IF;
 IF p_ends_at>now() AND p_ends_at<=p_starts_at THEN
  RAISE EXCEPTION 'O encerramento deve ocorrer depois do início' USING ERRCODE='22023'; END IF;
 IF NOT coalesce(p_multiple,false) AND EXISTS (
  SELECT 1 FROM public.poll_votes WHERE poll_id=p_poll GROUP BY user_id HAVING COUNT(*)>1
 ) THEN RAISE EXCEPTION 'Há coroinhas com várias respostas. Não é possível desativar essa opção.' USING ERRCODE='22023'; END IF;
 -- Existing IDs are preserved. A voted option cannot be renamed or removed.
 FOR v_item IN SELECT value FROM jsonb_array_elements(p_options) LOOP
  v_position:=v_position+1;
  IF jsonb_typeof(v_item)<>'object' THEN RAISE EXCEPTION 'Opção inválida' USING ERRCODE='22023'; END IF;
  v_label:=trim(coalesce(v_item->>'label',''));
  IF char_length(v_label) NOT BETWEEN 1 AND 140 THEN RAISE EXCEPTION 'Preencha todas as opções' USING ERRCODE='22023'; END IF;
  IF NULLIF(v_item->>'id','') IS NOT NULL THEN
   BEGIN v_id:=(v_item->>'id')::uuid;
   EXCEPTION WHEN invalid_text_representation THEN RAISE EXCEPTION 'Identificador da opção inválido' USING ERRCODE='22023'; END;
   IF NOT EXISTS(SELECT 1 FROM public.poll_options WHERE id=v_id AND poll_id=p_poll) THEN
    RAISE EXCEPTION 'Opção não pertence a esta enquete' USING ERRCODE='42501'; END IF;
   IF EXISTS(SELECT 1 FROM public.poll_votes WHERE poll_id=p_poll AND option_id=v_id)
      AND EXISTS(SELECT 1 FROM public.poll_options WHERE id=v_id AND label<>v_label) THEN
     RAISE EXCEPTION 'Esta opção já recebeu votos e não pode ser renomeada' USING ERRCODE='22023';
   END IF;
  ELSE
   v_id:=gen_random_uuid();
  END IF;
  IF v_id=ANY(v_ids) THEN RAISE EXCEPTION 'Opção repetida' USING ERRCODE='22023'; END IF;
  v_ids:=array_append(v_ids,v_id);
 END LOOP;
 IF EXISTS (SELECT 1 FROM public.poll_votes WHERE poll_id=p_poll AND NOT (option_id=ANY(v_ids))) THEN
  RAISE EXCEPTION 'Uma opção com votos não pode ser removida' USING ERRCODE='22023'; END IF;
 -- The unique (poll_id,position) index is respected by temporarily shifting positions.
 UPDATE public.poll_options SET position=position+100 WHERE poll_id=p_poll;
 DELETE FROM public.poll_options WHERE poll_id=p_poll AND NOT (id=ANY(v_ids));
 v_position:=0;
 FOR v_item IN SELECT value FROM jsonb_array_elements(p_options) LOOP
  v_position:=v_position+1;
  v_id:=v_ids[v_position];
  v_label:=trim(v_item->>'label');
  INSERT INTO public.poll_options(id,poll_id,label,position) VALUES(v_id,p_poll,v_label,v_position)
  ON CONFLICT (id) DO UPDATE SET label=EXCLUDED.label,position=EXCLUDED.position;
 END LOOP;
 UPDATE public.polls SET question=trim(p_question),starts_at=p_starts_at,
  ends_at=p_ends_at,multiple_answers=coalesce(p_multiple,false),priority=coalesce(p_priority,false)
 WHERE id=p_poll;
 RETURN jsonb_build_object('updated',true,'votes_preserved',v_vote_count);
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
  WHERE starts_at<=now() AND closed_at IS NULL AND ends_at>now() AND started_notified_at IS NULL
  ORDER BY starts_at FOR UPDATE SKIP LOCKED LOOP
  INSERT INTO public.notifications(user_id,title,body,event_key,priority,priority_until,group_id)
  SELECT id,'Nova enquete disponível',v.question,'polls',v.priority,v.ends_at,v.id
  FROM public.profiles WHERE approved AND role='coroinha';
  UPDATE public.polls SET started_notified_at=now() WHERE id=v.id;
  v_open:=v_open+1;
 END LOOP;
 FOR v IN SELECT * FROM public.polls
  WHERE started_notified_at IS NOT NULL AND reminder_notified_at IS NULL
  AND closed_at IS NULL AND ends_at>now() AND starts_at<=ends_at-interval '24 hours'
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
  WHERE (ends_at<=now() OR closed_at IS NOT NULL) AND closed_notified_at IS NULL
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

CREATE OR REPLACE FUNCTION public.archive_maintenance()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE result jsonb := '{}'::jsonb; n integer;
BEGIN
 IF NOT public.automation_enabled('archive_retention') THEN
  RETURN jsonb_build_object('enabled',false,'status','disabled');
 END IF;
 -- Only one maintenance run at a time, even if both Vercel Cron and a live client call.
 IF NOT pg_try_advisory_xact_lock(937144001) THEN
  RETURN jsonb_build_object('enabled',true,'status','already_running');
 END IF;
 -- A mass is archived 24 hours after its actual scheduled start time.
 UPDATE public.masses SET archived_at=now()
 WHERE archived_at IS NULL AND starts_at <= now()-interval '24 hours';
 GET DIAGNOSTICS n=ROW_COUNT;
 result:=result||jsonb_build_object('masses_archived',n);
 UPDATE public.notifications SET archived_at=now()
 WHERE archived_at IS NULL AND created_at<=now()-interval '30 days';
 GET DIAGNOSTICS n=ROW_COUNT;
 result:=result||jsonb_build_object('notifications_archived',n);
 -- Keep poll available while open; start counting after closing.
 UPDATE public.polls SET archived_at=now()
 WHERE archived_at IS NULL AND coalesce(closed_at,ends_at)<=now()-interval '30 days';
 GET DIAGNOSTICS n=ROW_COUNT;
 result:=result||jsonb_build_object('polls_archived',n);
 UPDATE public.screen_announcements SET archived_at=now(),active=false
 WHERE archived_at IS NULL AND created_at<=now()-interval '30 days';
 GET DIAGNOSTICS n=ROW_COUNT;
 result:=result||jsonb_build_object('announcements_archived',n);
 UPDATE public.messages SET archived_at=now()
 WHERE archived_at IS NULL AND created_at<=now()-interval '30 days';
 GET DIAGNOSTICS n=ROW_COUNT;
 result:=result||jsonb_build_object('messages_archived',n);
 -- Never delete an open support conversation; start retention after closure.
 UPDATE public.support_tickets SET archived_at=now()
 WHERE archived_at IS NULL AND status='encerrado'
 AND coalesce(closed_at,updated_at,created_at)<=now()-interval '30 days';
 GET DIAGNOSTICS n=ROW_COUNT;
 result:=result||jsonb_build_object('support_archived',n);

 -- Keep answered questions available for 30 days after the deadline before archive.
 UPDATE public.open_questions SET archived_at=now()
 WHERE archived_at IS NULL AND ends_at<=now()-interval '30 days';
 GET DIAGNOSTICS n=ROW_COUNT;
 result:=result||jsonb_build_object('questions_archived',n);
  -- Retain archived records for another 30 full days.
 DELETE FROM public.notifications WHERE archived_at<=now()-interval '30 days';
 GET DIAGNOSTICS n=ROW_COUNT;
 result:=result||jsonb_build_object('notifications_removed',n);
 DELETE FROM public.messages WHERE archived_at<=now()-interval '30 days';
 GET DIAGNOSTICS n=ROW_COUNT;
 result:=result||jsonb_build_object('messages_removed',n);
 DELETE FROM public.screen_announcements WHERE archived_at<=now()-interval '30 days';
 GET DIAGNOSTICS n=ROW_COUNT;
 result:=result||jsonb_build_object('announcements_removed',n);
 DELETE FROM public.open_questions WHERE archived_at<=now()-interval '30 days';
 GET DIAGNOSTICS n=ROW_COUNT;
 result:=result||jsonb_build_object('questions_removed',n);
  DELETE FROM public.polls WHERE archived_at<=now()-interval '30 days';
 GET DIAGNOSTICS n=ROW_COUNT;
 result:=result||jsonb_build_object('polls_removed',n);
 DELETE FROM public.support_tickets WHERE archived_at<=now()-interval '30 days';
 GET DIAGNOSTICS n=ROW_COUNT;
 result:=result||jsonb_build_object('support_removed',n);
 DELETE FROM public.masses WHERE archived_at<=now()-interval '30 days';
 GET DIAGNOSTICS n=ROW_COUNT;
 result:=result||jsonb_build_object('masses_removed',n);
 RETURN result||jsonb_build_object('enabled',true,'status','ok');
END $function$
;
