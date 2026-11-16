-- QA testado em 16/11/2026. Executar na produção SOMENTE com autorização específica.
-- Enquetes: público-alvo selecionável, validado no servidor e na fila de notificações.
-- Perguntas: coordenação pode selecionar coroinha, cerimoniario ou todos.
-- Mensagens: já possuem segmentação via send_notification_targeted.
BEGIN;
ALTER TABLE public.polls ADD COLUMN IF NOT EXISTS target_role text NOT NULL DEFAULT 'todos';
ALTER TABLE public.polls DROP CONSTRAINT IF EXISTS polls_target_role_check;
ALTER TABLE public.polls ADD CONSTRAINT polls_target_role_check CHECK (target_role IN ('coroinha','cerimoniario','todos'));

CREATE OR REPLACE FUNCTION public.poll_create_targeted(p_question text, p_options jsonb, p_starts_at timestamp with time zone, p_ends_at timestamp with time zone, p_multiple boolean, p_priority boolean, p_target text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_id uuid;v_n int;
BEGIN
 IF NOT public.has_site_permission('manage_polls') THEN RAISE EXCEPTION 'Sem permissão para esta ação' USING ERRCODE='42501'; END IF;

 IF p_target NOT IN ('coroinha','cerimoniario','todos') OR p_target IS NULL THEN RAISE EXCEPTION 'Público inválido' USING ERRCODE='22023'; END IF;
 -- Access controlled by has_site_permission at function entry.
 IF char_length(trim(coalesce(p_question,''))) NOT BETWEEN 5 AND 250 THEN RAISE EXCEPTION 'A pergunta precisa ter entre 5 e 250 caracteres' USING ERRCODE='22023'; END IF;
 IF p_starts_at IS NULL OR p_ends_at IS NULL OR p_ends_at<=p_starts_at OR p_ends_at<=now()
  OR p_starts_at<now()-interval '5 minutes' THEN RAISE EXCEPTION 'Verifique as datas de início e encerramento' USING ERRCODE='22023'; END IF;
 IF jsonb_typeof(p_options)<>'array' THEN RAISE EXCEPTION 'Informe as opções de resposta' USING ERRCODE='22023'; END IF;
 v_n:=jsonb_array_length(p_options);
 IF v_n NOT BETWEEN 2 AND 10 OR EXISTS(SELECT 1 FROM jsonb_array_elements_text(p_options) AS x(value) WHERE length(trim(x.value)) NOT BETWEEN 1 AND 140)
 THEN RAISE EXCEPTION 'Informe de 2 a 10 opções válidas' USING ERRCODE='22023'; END IF;
 INSERT INTO public.polls(question,starts_at,ends_at,multiple_answers,priority,created_by,target_role)
 VALUES(trim(p_question),p_starts_at,p_ends_at,coalesce(p_multiple,false),coalesce(p_priority,false),auth.uid(),p_target) RETURNING id INTO v_id;
 INSERT INTO public.poll_options(poll_id,label,position)
 SELECT v_id,trim(x.value),x.ordinality::integer FROM jsonb_array_elements_text(p_options) WITH ORDINALITY AS x(value,ordinality);
 PERFORM public.poll_dispatch();
 RETURN v_id;
END $function$
;

CREATE OR REPLACE FUNCTION public.poll_update_targeted(p_poll uuid, p_question text, p_options jsonb, p_starts_at timestamp with time zone, p_ends_at timestamp with time zone, p_multiple boolean, p_priority boolean, p_target text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_poll public.polls%ROWTYPE;v_item jsonb;v_id uuid;v_label text;v_position int:=0;v_ids uuid[]:=ARRAY[]::uuid[];v_vote_count bigint;
BEGIN
 IF NOT public.has_site_permission('manage_polls') THEN RAISE EXCEPTION 'Sem permissão para esta ação' USING ERRCODE='42501'; END IF;

 IF p_target NOT IN ('coroinha','cerimoniario','todos') OR p_target IS NULL THEN RAISE EXCEPTION 'Público inválido' USING ERRCODE='22023'; END IF;
 -- Access controlled by has_site_permission at function entry.
 SELECT * INTO v_poll FROM public.polls WHERE id=p_poll FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Enquete não encontrada' USING ERRCODE='22023'; END IF;
 IF v_poll.target_role<>p_target AND EXISTS(SELECT 1 FROM public.poll_votes WHERE poll_id=p_poll) THEN RAISE EXCEPTION 'O público não pode mudar depois de receber votos' USING ERRCODE='22023'; END IF;
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
  ends_at=p_ends_at,multiple_answers=coalesce(p_multiple,false),priority=coalesce(p_priority,false),target_role=p_target
 WHERE id=p_poll;
 RETURN jsonb_build_object('updated',true,'votes_preserved',v_vote_count);
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
    'id',p.id,'created_by',p.created_by,'target_role',p.target_role,'question',CASE WHEN v_coord OR now()<p.ends_at THEN p.question ELSE 'Enquete encerrada' END,
    'starts_at',p.starts_at,'ends_at',p.ends_at,
    'multiple_answers',CASE WHEN v_coord OR now()<p.ends_at THEN p.multiple_answers ELSE false END,
    'priority',p.priority,
    'state',CASE WHEN p.closed_at IS NOT NULL THEN 'encerrada' WHEN now()<p.starts_at THEN 'agendada' WHEN now()>=p.ends_at THEN 'encerrada' ELSE 'aberta' END,
    'voted',EXISTS(SELECT 1 FROM public.poll_votes v WHERE v.poll_id=p.id AND v.user_id=v_user),
    'my_options',CASE WHEN public.has_site_permission('vote_polls') AND now()>=p.starts_at AND now()<p.ends_at
       THEN (SELECT coalesce(jsonb_agg(v.option_id ORDER BY o.position),'[]'::jsonb)
        FROM public.poll_votes v
        JOIN public.poll_options o ON o.id=v.option_id AND o.poll_id=v.poll_id
        WHERE v.poll_id=p.id AND v.user_id=v_user)
       ELSE '[]'::jsonb END,
    'options',CASE WHEN v_coord OR (now()>=p.starts_at AND now()<p.ends_at AND public.has_site_permission('vote_polls'))
      THEN (SELECT coalesce(jsonb_agg(jsonb_build_object('id',o.id,'label',o.label,'position',o.position) ORDER BY o.position),'[]'::jsonb)
        FROM public.poll_options o WHERE o.poll_id=p.id)
      ELSE '[]'::jsonb END,
    'results',CASE WHEN v_coord THEN (SELECT coalesce(jsonb_agg(jsonb_build_object(
       'id',o.id,'label',o.label,
       'votes',(SELECT count(*) FROM public.poll_votes v WHERE v.poll_id=p.id AND v.option_id=o.id),
       'voters',(SELECT coalesce(jsonb_agg(jsonb_build_object(
        'name',coalesce(nullif(trim(pr.name),''),'Integrante sem nome'),
        'role',CASE WHEN pr.role='cerimoniario' OR (pr.role='coordenadora' AND pr.coordination_group='cerimoniario') THEN 'cerimoniario' ELSE 'coroinha' END,
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
  WHERE p.archived_at IS NULL AND (v_coord OR (public.has_site_permission('vote_polls') AND p.starts_at<=now() AND (p.target_role='todos' OR p.target_role=(SELECT role FROM public.profiles WHERE id=v_user))))
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
 IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id=v_user AND approved AND (v_poll.target_role='todos' AND role IN ('coroinha','cerimoniario') OR v_poll.target_role=role)) THEN RAISE EXCEPTION 'Enquete para outro público' USING ERRCODE='42501'; END IF;
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
  SELECT 1 FROM public.profiles WHERE id=v_user AND approved
 ) THEN RAISE EXCEPTION 'Usuário sem permissão para responder enquetes' USING ERRCODE='42501'; END IF;
 SELECT * INTO v_poll FROM public.polls WHERE id=p_poll FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Enquete não encontrada' USING ERRCODE='22023'; END IF;
 IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id=v_user AND approved AND (v_poll.target_role='todos' AND role IN ('coroinha','cerimoniario') OR v_poll.target_role=role)) THEN RAISE EXCEPTION 'Enquete para outro público' USING ERRCODE='42501'; END IF;
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
  FROM public.profiles WHERE approved AND role IN ('coroinha','cerimoniario') AND (v.target_role='todos' OR role=v.target_role);
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
  FROM public.profiles p WHERE p.approved AND p.role IN ('coroinha','cerimoniario') AND (v.target_role='todos' OR p.role=v.target_role)
  AND NOT EXISTS(SELECT 1 FROM public.poll_votes x WHERE x.poll_id=v.id AND x.user_id=p.id);
  UPDATE public.polls SET reminder_notified_at=now() WHERE id=v.id;
  v_rem:=v_rem+1;
 END LOOP;
 FOR v IN SELECT * FROM public.polls
  WHERE (ends_at<=now() OR closed_at IS NOT NULL) AND closed_notified_at IS NULL
  ORDER BY ends_at FOR UPDATE SKIP LOCKED LOOP
  INSERT INTO public.notifications(user_id,title,body,event_key,group_id)
  SELECT p.id,'Enquete encerrada','O prazo da enquete foi encerrado.','polls',v.id
  FROM public.profiles p WHERE p.approved AND p.role IN ('coroinha','cerimoniario') AND (v.target_role='todos' OR p.role=v.target_role);
  UPDATE public.polls SET closed_notified_at=now() WHERE id=v.id;
  v_closed:=v_closed+1;
 END LOOP;
 RETURN jsonb_build_object('abertas',v_open,'lembretes',v_rem,'encerradas',v_closed);
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
 -- A coordenação pode selecionar público entre coroinhas, cerimoniários ou todos.
 IF p_target NOT IN ('coroinha','cerimoniario','todos') AND v_role<>'desenvolvedor' THEN RAISE EXCEPTION 'Público inválido para esta função' USING ERRCODE='42501'; END IF;
 IF length(trim(coalesce(p_question,''))) NOT BETWEEN 5 AND 500 THEN RAISE EXCEPTION 'Escreva uma pergunta de 5 a 500 caracteres' USING ERRCODE='22023'; END IF;
 IF p_ends_at<=now() OR p_ends_at>now()+interval '90 days' THEN RAISE EXCEPTION 'Prazo inválido' USING ERRCODE='22023'; END IF;
 INSERT INTO public.open_questions(question,target_role,created_by,ends_at)
 VALUES(trim(p_question),p_target,v_user,p_ends_at) RETURNING id INTO v_id;
 INSERT INTO public.notifications(user_id,title,body,event_key,group_id,priority_until)
 SELECT p.id,'Nova pergunta para responder',left(trim(p_question),400),'open_questions',v_id,p_ends_at
 FROM public.profiles p WHERE p.approved AND p.id<>v_user
 AND (p_target='todos' AND p.role IN ('coroinha','cerimoniario') OR p.role=p_target)
 AND p.role<>'desenvolvedor';
 RETURN v_id;
END $function$
;

CREATE OR REPLACE FUNCTION public.open_question_list()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_user uuid:=auth.uid();v_role text;v_group text;
BEGIN
 IF v_user IS NULL OR NOT public.is_approved() THEN RAISE EXCEPTION 'Acesso negado' USING ERRCODE='42501'; END IF;
 SELECT role,coordination_group INTO v_role,v_group FROM public.profiles WHERE id=v_user;
 RETURN coalesce((
 SELECT jsonb_agg(jsonb_build_object(
 'id',q.id,'question',q.question,'ends_at',q.ends_at,'created_at',q.created_at,'target_role',q.target_role,
 'created_by',q.created_by,'creator_name',p.name,'answer',a.answer,
 'answer_count',CASE WHEN public.has_site_permission('manage_polls') AND (v_role='desenvolvedor' OR q.created_by=v_user) THEN
 (SELECT count(*) FROM public.open_question_answers x WHERE x.question_id=q.id) ELSE NULL END
 ) ORDER BY q.created_at DESC)
 FROM public.open_questions q JOIN public.profiles p ON p.id=q.created_by
 LEFT JOIN public.open_question_answers a ON a.question_id=q.id AND a.user_id=v_user
 WHERE q.archived_at IS NULL AND (
 (q.ends_at>now() AND (q.target_role='todos' AND v_role IN ('coroinha','cerimoniario') OR q.target_role=v_role))
 OR (public.has_site_permission('manage_polls') AND (v_role='desenvolvedor' OR q.created_by=v_user))
 )
 ),'[]'::jsonb);
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
 IF NOT (v_q.target_role='todos' AND v_role IN ('coroinha','cerimoniario') OR v_q.target_role=v_role) THEN RAISE EXCEPTION 'Pergunta de outro público' USING ERRCODE='42501'; END IF;
 IF length(trim(coalesce(p_answer,''))) NOT BETWEEN 1 AND 2000 THEN RAISE EXCEPTION 'Resposta deve ter até 2000 caracteres' USING ERRCODE='22023'; END IF;
 INSERT INTO public.open_question_answers(question_id,user_id,answer) VALUES(p_question,v_user,trim(p_answer))
 ON CONFLICT(question_id,user_id) DO NOTHING;
 IF NOT FOUND THEN RAISE EXCEPTION 'Você já respondeu esta pergunta' USING ERRCODE='22023'; END IF;
 INSERT INTO public.notifications(user_id,title,body,event_key)
 VALUES(v_q.created_by,'Nova resposta recebida',left(trim(p_answer),300),'general');
 RETURN true;
END $function$
;

REVOKE ALL ON FUNCTION public.poll_create_targeted(text,jsonb,timestamptz,timestamptz,boolean,boolean,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.poll_update_targeted(uuid,text,jsonb,timestamptz,timestamptz,boolean,boolean,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.poll_create_targeted(text,jsonb,timestamptz,timestamptz,boolean,boolean,text) TO coroinhas_app;
GRANT EXECUTE ON FUNCTION public.poll_update_targeted(uuid,text,jsonb,timestamptz,timestamptz,boolean,boolean,text) TO coroinhas_app;
COMMIT;
