-- Alinha funções com as permissões delegadas pelo Desenvolvedor.
-- Os controles de segurança permanecem no banco (has_site_permission).

CREATE OR REPLACE FUNCTION public.edit_notification(p_group uuid, p_title text, p_body text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
 IF NOT public.has_site_permission('send_notifications') THEN RAISE EXCEPTION 'Acesso negado'; END IF;
 IF length(trim(coalesce(p_title,'')))=0 OR length(trim(coalesce(p_body,'')))=0 THEN RAISE EXCEPTION 'Preencha titulo e mensagem'; END IF;
 UPDATE public.notifications SET title=trim(p_title),body=trim(p_body),seen=false,read_at=NULL,created_at=now() WHERE group_id=p_group;
 IF NOT FOUND THEN RAISE EXCEPTION 'Aviso nao encontrado'; END IF;
END $function$;

CREATE OR REPLACE FUNCTION public.send_notification(p_title text, p_body text, p_recipient uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_group uuid:=gen_random_uuid();
BEGIN
 IF NOT public.has_site_permission('send_notifications') THEN RAISE EXCEPTION 'Sem permissão para esta ação' USING ERRCODE='42501'; END IF;

 -- Access controlled by has_site_permission at function entry.
 IF length(trim(coalesce(p_title,'')))=0 OR length(trim(coalesce(p_body,'')))=0 THEN RAISE EXCEPTION 'Preencha titulo e mensagem'; END IF;
 INSERT INTO public.notifications(user_id,title,body,group_id,seen,read_at)
 SELECT p.id,trim(p_title),trim(p_body),v_group,false,NULL FROM public.profiles p
 WHERE p.approved=true AND p.role='coroinha' AND (p_recipient IS NULL OR p.id=p_recipient);
 IF NOT FOUND THEN RAISE EXCEPTION 'Nenhum destinatario encontrado'; END IF;
 RETURN v_group;
END $function$;

CREATE OR REPLACE FUNCTION public.poll_create(p_question text, p_options jsonb, p_starts_at timestamp with time zone, p_ends_at timestamp with time zone, p_multiple boolean, p_priority boolean)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_id uuid;v_n int;
BEGIN
 IF NOT public.has_site_permission('manage_polls') THEN RAISE EXCEPTION 'Sem permissão para esta ação' USING ERRCODE='42501'; END IF;

 -- Access controlled by has_site_permission at function entry.
 IF char_length(trim(coalesce(p_question,''))) NOT BETWEEN 5 AND 250 THEN RAISE EXCEPTION 'A pergunta precisa ter entre 5 e 250 caracteres' USING ERRCODE='22023'; END IF;
 IF p_starts_at IS NULL OR p_ends_at IS NULL OR p_ends_at<=p_starts_at OR p_ends_at<=now()
  OR p_starts_at<now()-interval '5 minutes' THEN RAISE EXCEPTION 'Verifique as datas de início e encerramento' USING ERRCODE='22023'; END IF;
 IF jsonb_typeof(p_options)<>'array' THEN RAISE EXCEPTION 'Informe as opções de resposta' USING ERRCODE='22023'; END IF;
 v_n:=jsonb_array_length(p_options);
 IF v_n NOT BETWEEN 2 AND 10 OR EXISTS(SELECT 1 FROM jsonb_array_elements_text(p_options) AS x(value) WHERE length(trim(x.value)) NOT BETWEEN 1 AND 140)
 THEN RAISE EXCEPTION 'Informe de 2 a 10 opções válidas' USING ERRCODE='22023'; END IF;
 INSERT INTO public.polls(question,starts_at,ends_at,multiple_answers,priority,created_by)
 VALUES(trim(p_question),p_starts_at,p_ends_at,coalesce(p_multiple,false),coalesce(p_priority,false),auth.uid()) RETURNING id INTO v_id;
 INSERT INTO public.poll_options(poll_id,label,position)
 SELECT v_id,trim(x.value),x.ordinality::integer FROM jsonb_array_elements_text(p_options) WITH ORDINALITY AS x(value,ordinality);
 PERFORM public.poll_dispatch();
 RETURN v_id;
END $function$;

CREATE OR REPLACE FUNCTION public.developer_usage_summary()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
 IF NOT public.has_site_permission('view_developer_panel') THEN RAISE EXCEPTION 'Sem permissão para esta ação' USING ERRCODE='42501'; END IF;

 -- Access controlled by view_developer_panel permission.
 RETURN jsonb_build_object(
 'total_users',(SELECT count(*) FROM public.profiles),
 'approved_users',(SELECT count(*) FROM public.profiles WHERE approved),
 'pending_users',(SELECT count(*) FROM public.profiles WHERE NOT approved),
 'servers',(SELECT count(*) FROM public.profiles WHERE role='coroinha' AND approved),
 'parents',(SELECT count(*) FROM public.profiles WHERE role='pai' AND approved),
 'coordinators',(SELECT count(*) FROM public.profiles WHERE role='coordenadora' AND approved),
 'developers',(SELECT count(*) FROM public.profiles WHERE role='desenvolvedor' AND approved),
 'active_24h',(SELECT count(*) FROM public.profiles WHERE last_seen_at >= now()-interval '24 hours'),
 'logins_recorded',(SELECT count(*) FROM public.login_events),
 'db_size_bytes',pg_database_size(current_database()),
 'masses',(SELECT count(*) FROM public.masses),
 'notifications',(SELECT count(*) FROM public.notifications));
END $function$;

CREATE OR REPLACE FUNCTION public.create_mass_with_assignments(p_title text, p_starts_at timestamp with time zone, p_location text, p_celebrant text, p_notes text, p_roles jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_user uuid:=auth.uid();v_mass uuid;v_count int;v_item jsonb;v_fn text;v_server uuid;v_group text;
BEGIN
 IF NOT public.has_site_permission('create_scales') THEN RAISE EXCEPTION 'Sem permissão para esta ação' USING ERRCODE='42501'; END IF;

 -- Access controlled by has_site_permission at function entry.
 IF length(trim(coalesce(p_title,''))) NOT BETWEEN 2 AND 180 OR p_starts_at IS NULL THEN
  RAISE EXCEPTION 'Informe o nome, a data e o horário da missa' USING ERRCODE='22023';
 END IF;
 IF jsonb_typeof(p_roles)<>'array' THEN
  RAISE EXCEPTION 'Funções inválidas' USING ERRCODE='22023';
 END IF;
 v_count:=jsonb_array_length(p_roles);
 IF v_count>80 THEN RAISE EXCEPTION 'Há funções demais nesta missa' USING ERRCODE='22023'; END IF;
 FOR v_item IN SELECT value FROM jsonb_array_elements(p_roles) LOOP
  IF jsonb_typeof(v_item)<>'object' THEN RAISE EXCEPTION 'Função inválida' USING ERRCODE='22023'; END IF;
  v_fn:=trim(coalesce(v_item->>'fn',''));
  v_group:=coalesce(nullif(v_item->>'group',''),'coroinha');
  IF v_group NOT IN ('coroinha','cerimoniario') OR NOT public.can_manage_service_group(v_group) THEN RAISE EXCEPTION 'Grupo de função inválido para esta coordenação' USING ERRCODE='42501'; END IF;
  IF length(v_fn) NOT BETWEEN 1 AND 120 THEN RAISE EXCEPTION 'Preencha todas as funções' USING ERRCODE='22023'; END IF;
  IF nullif(v_item->>'uid','') IS NOT NULL THEN
   BEGIN v_server:=(v_item->>'uid')::uuid;
   EXCEPTION WHEN invalid_text_representation THEN RAISE EXCEPTION 'Coroinha selecionado inválido' USING ERRCODE='22023'; END;
   IF NOT EXISTS(SELECT 1 FROM public.profiles WHERE id=v_server AND approved AND role=v_group)
   THEN RAISE EXCEPTION 'O coroinha selecionado não está aprovado' USING ERRCODE='22023'; END IF;
  END IF;
 END LOOP;
 -- Serializa tentativas simultâneas da mesma conta para evitar missa duplicada.
 PERFORM pg_advisory_xact_lock(hashtextextended(v_user::text||p_starts_at::text||trim(p_title),31));
 SELECT m.id INTO v_mass FROM public.masses m
 WHERE m.created_by=v_user AND m.title=trim(p_title) AND m.starts_at=p_starts_at
 ORDER BY m.created_at DESC LIMIT 1 FOR UPDATE;
 IF v_mass IS NOT NULL THEN
  IF EXISTS(SELECT 1 FROM public.assignments WHERE mass_id=v_mass) THEN
   RAISE EXCEPTION 'Esta missa já está cadastrada. Abra-a para editar as funções.' USING ERRCODE='P0001';
  END IF;
  -- Corrige apenas uma criação incompleta da própria conta.
  UPDATE public.masses SET location=coalesce(p_location,''),celebrant=coalesce(p_celebrant,''),
   notes=coalesce(p_notes,''),published=true WHERE id=v_mass;
 ELSE
  INSERT INTO public.masses(title,starts_at,location,celebrant,notes,published,created_by)
  VALUES(trim(p_title),p_starts_at,coalesce(p_location,''),coalesce(p_celebrant,''),
   coalesce(p_notes,''),true,v_user) RETURNING id INTO v_mass;
 END IF;
 FOR v_item IN SELECT value FROM jsonb_array_elements(p_roles) LOOP
  v_server:=NULLIF(v_item->>'uid','')::uuid;
  INSERT INTO public.assignments(mass_id,function_name,server_id,status,service_group)
  VALUES(v_mass,trim(v_item->>'fn'),v_server,'escalado',coalesce(nullif(v_item->>'group',''),'coroinha'));
 END LOOP;
 RETURN v_mass;
END $function$;

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
    'id',p.id,'question',CASE WHEN v_coord OR now()<p.ends_at THEN p.question ELSE 'Enquete encerrada' END,
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
  WHERE v_coord OR (r.role='coroinha' AND p.starts_at<=now())
 ),'[]'::jsonb);
END $function$;

CREATE OR REPLACE FUNCTION public.send_notification_prioritized(p_title text, p_body text, p_target text, p_recipient uuid, p_priority boolean, p_priority_until timestamp with time zone)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_group uuid;
BEGIN
 IF NOT public.has_site_permission('send_notifications') THEN RAISE EXCEPTION 'Sem permissão para esta ação' USING ERRCODE='42501'; END IF;

 -- Access controlled by has_site_permission at function entry.
 IF coalesce(p_priority,false) AND (p_priority_until IS NULL OR p_priority_until<=now()) THEN
  RAISE EXCEPTION 'Informe um prazo futuro para a notificação prioritária' USING ERRCODE='22023'; END IF;
 v_group:=public.send_notification_targeted(p_title,p_body,p_target,p_recipient);
 IF coalesce(p_priority,false) THEN
  UPDATE public.notifications SET priority=true,priority_until=p_priority_until WHERE group_id=v_group;
 END IF;
 RETURN v_group;
END $function$;

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
END $function$;

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
 IF p_target NOT IN ('coroinha','pai','coordenadora','todos','individual') OR p_target IS NULL THEN
  RAISE EXCEPTION 'Destinatário inválido' USING ERRCODE='22023';
 END IF;
 IF (p_target='individual' AND p_recipient IS NULL) OR (p_target<>'individual' AND p_recipient IS NOT NULL) THEN
  RAISE EXCEPTION 'Seleção de destinatários inválida' USING ERRCODE='22023';
 END IF;
 INSERT INTO public.notifications(user_id,title,body,group_id,seen,read_at,event_key)
 SELECT p.id, trim(p_title), trim(p_body), v_group, false, NULL,
 CASE WHEN p_target='individual' THEN 'direct_message' ELSE 'general' END
 FROM public.profiles p
 WHERE p.approved = true
 AND (
  p_target='todos'
  OR (p_target='individual' AND p.id=p_recipient)
  OR (p_target IN ('coroinha','pai','coordenadora') AND p.role=p_target)
 );
 GET DIAGNOSTICS v_count = ROW_COUNT;
 IF v_count=0 THEN RAISE EXCEPTION 'Nenhum destinatário aprovado encontrado para o grupo selecionado.' USING ERRCODE='P0001'; END IF;
 RETURN v_group;
END
$function$;

CREATE OR REPLACE FUNCTION public.delete_notification(p_group uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
 IF NOT public.has_site_permission('send_notifications') THEN RAISE EXCEPTION 'Acesso negado'; END IF;
 DELETE FROM public.notifications WHERE group_id=p_group;
END $function$;

CREATE OR REPLACE FUNCTION public.developer_recent_access(p_role text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
 IF NOT public.has_site_permission('view_developer_panel') THEN RAISE EXCEPTION 'Sem permissão para esta ação' USING ERRCODE='42501'; END IF;

 -- Access controlled by view_developer_panel permission.
 IF p_role IS NULL OR p_role NOT IN ('coroinha','pai','coordenadora') THEN
  RAISE EXCEPTION 'Perfil inválido' USING ERRCODE='22023';
 END IF;
 RETURN coalesce((
   SELECT jsonb_agg(jsonb_build_object(
     'name',p.name,'email',p.email,
     'last_seen_at',p.last_seen_at,
     'active_24h',p.last_seen_at >= now()-interval '24 hours'
   ) ORDER BY p.last_seen_at DESC NULLS LAST,p.name)
   FROM public.profiles p WHERE p.approved AND p.role=p_role
 ),'[]'::jsonb);
END $function$;
