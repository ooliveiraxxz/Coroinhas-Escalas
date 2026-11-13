-- ESCALA SÃO BENTO - REVISÃO DE PERMISSÕES (HOMOLOGAÇÃO)
-- AINDA NÃO EXECUTAR NA PRODUÇÃO. Testar antes com contas fictícias.
-- Responder enquetes: não restringir a função ao nome do perfil quando existe permissão vote_polls.
BEGIN;

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
  WHERE p.archived_at IS NULL AND (v_coord OR (public.has_site_permission('vote_polls') AND p.starts_at<=now()))
 ),'[]'::jsonb);
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
  FROM public.profiles WHERE approved AND role IN ('coroinha','cerimoniario');
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
  FROM public.profiles p WHERE p.approved AND p.role IN ('coroinha','cerimoniario')
  AND NOT EXISTS(SELECT 1 FROM public.poll_votes x WHERE x.poll_id=v.id AND x.user_id=p.id);
  UPDATE public.polls SET reminder_notified_at=now() WHERE id=v.id;
  v_rem:=v_rem+1;
 END LOOP;
 FOR v IN SELECT * FROM public.polls
  WHERE (ends_at<=now() OR closed_at IS NOT NULL) AND closed_notified_at IS NULL
  ORDER BY ends_at FOR UPDATE SKIP LOCKED LOOP
  INSERT INTO public.notifications(user_id,title,body,event_key,group_id)
  SELECT p.id,'Enquete encerrada','O prazo da enquete foi encerrado.','polls',v.id
  FROM public.profiles p WHERE p.approved AND p.role IN ('coroinha','cerimoniario');
  UPDATE public.polls SET closed_notified_at=now() WHERE id=v.id;
  v_closed:=v_closed+1;
 END LOOP;
 RETURN jsonb_build_object('abertas',v_open,'lembretes',v_rem,'encerradas',v_closed);
END $function$
;

COMMIT;
