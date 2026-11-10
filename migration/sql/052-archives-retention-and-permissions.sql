-- 052: Archivamento e descarte automático de conteúdos operacionais
-- Prérequisito: 045/044 e migrações anteriores. Fuso de exibição: America/Sao_Paulo.
-- As funções guardam dados por 30 dias adicionais após a data de arquivamento.
-- Este script não executa automaticamente limpeza no momento da migração.

ALTER TABLE public.masses ADD COLUMN IF NOT EXISTS archived_at timestamptz;
ALTER TABLE public.notifications ADD COLUMN IF NOT EXISTS archived_at timestamptz;
ALTER TABLE public.polls ADD COLUMN IF NOT EXISTS archived_at timestamptz;
ALTER TABLE public.screen_announcements ADD COLUMN IF NOT EXISTS archived_at timestamptz;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS archived_at timestamptz;
ALTER TABLE public.support_tickets ADD COLUMN IF NOT EXISTS archived_at timestamptz;

INSERT INTO public.permission_catalog(key,category,label,default_roles,sensitive)
 VALUES('view_archives','Desenvolvedor','Visualizar Arquivados',ARRAY['desenvolvedor']::text[],true)
 ON CONFLICT(key) DO UPDATE SET category=EXCLUDED.category,label=EXCLUDED.label,default_roles=EXCLUDED.default_roles,sensitive=EXCLUDED.sensitive;
INSERT INTO public.automation_catalog(key,label,description,implemented)
 VALUES('archive_retention','Arquivamento e exclusão automática',
 'Arquiva missas 24 horas depois; notificações, enquetes, avisos e mensagens após 30 dias; exclui após outros 30 dias.',true)
 ON CONFLICT(key) DO UPDATE SET label=EXCLUDED.label,description=EXCLUDED.description,implemented=EXCLUDED.implemented;
INSERT INTO public.service_settings(key,enabled,updated_at)
 VALUES('archive_retention',true,now()) ON CONFLICT(key) DO NOTHING;

CREATE INDEX IF NOT EXISTS masses_archive_retention_idx ON public.masses USING btree (archived_at) WHERE (archived_at IS NOT NULL);
CREATE INDEX IF NOT EXISTS masses_archive_schedule_idx ON public.masses USING btree (starts_at) WHERE (archived_at IS NULL);
CREATE INDEX IF NOT EXISTS messages_archive_retention_idx ON public.messages USING btree (archived_at) WHERE (archived_at IS NOT NULL);
CREATE INDEX IF NOT EXISTS messages_archive_schedule_idx ON public.messages USING btree (created_at) WHERE (archived_at IS NULL);
CREATE INDEX IF NOT EXISTS notifications_archive_retention_idx ON public.notifications USING btree (archived_at) WHERE (archived_at IS NOT NULL);
CREATE INDEX IF NOT EXISTS notifications_archive_schedule_idx ON public.notifications USING btree (created_at) WHERE (archived_at IS NULL);
CREATE INDEX IF NOT EXISTS polls_archive_retention_idx ON public.polls USING btree (archived_at) WHERE (archived_at IS NOT NULL);
CREATE INDEX IF NOT EXISTS polls_archive_schedule_idx ON public.polls USING btree (created_at) WHERE (archived_at IS NULL);
CREATE INDEX IF NOT EXISTS announcements_archive_retention_idx ON public.screen_announcements USING btree (archived_at) WHERE (archived_at IS NOT NULL);
CREATE INDEX IF NOT EXISTS screen_announcements_archive_schedule_idx ON public.screen_announcements USING btree (created_at) WHERE (archived_at IS NULL);
CREATE INDEX IF NOT EXISTS support_archive_retention_idx ON public.support_tickets USING btree (archived_at) WHERE (archived_at IS NOT NULL);
CREATE INDEX IF NOT EXISTS support_tickets_archive_schedule_idx ON public.support_tickets USING btree (closed_at) WHERE (archived_at IS NULL);

CREATE OR REPLACE FUNCTION public.archive_list()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
 IF auth.uid() IS NULL OR NOT public.has_site_permission('view_archives') THEN
  RAISE EXCEPTION 'Acesso aos arquivados não autorizado' USING ERRCODE='42501';
 END IF;
 RETURN jsonb_build_object(
  'masses',coalesce((SELECT jsonb_agg(jsonb_build_object(
    'id',m.id,'title',m.title,'starts_at',m.starts_at,
    'location',m.location,'archived_at',m.archived_at,
    'expires_at',m.archived_at+interval '30 days',
    'assignments',(SELECT coalesce(jsonb_agg(jsonb_build_object(
      'function_name',a.function_name,'service_group',a.service_group,
      'status',a.status,'server',coalesce(p.name,'Vaga disponível')
    ) ORDER BY a.function_name),'[]'::jsonb)
    FROM public.assignments a LEFT JOIN public.profiles p ON p.id=a.server_id
    WHERE a.mass_id=m.id)
   ) ORDER BY m.starts_at DESC)
   FROM (SELECT * FROM public.masses WHERE archived_at IS NOT NULL ORDER BY starts_at DESC LIMIT 200)m),'[]'::jsonb),
  'notifications',coalesce((SELECT jsonb_agg(jsonb_build_object(
    'title',n.title,'body',n.body,'created_at',n.created_at,
    'archived_at',n.archived_at,'expires_at',n.archived_at+interval '30 days'
  ) ORDER BY n.created_at DESC)
  FROM (SELECT * FROM public.notifications WHERE archived_at IS NOT NULL AND
    (public.is_developer() OR user_id=auth.uid()) ORDER BY created_at DESC LIMIT 200)n),'[]'::jsonb),
  'polls',coalesce((SELECT jsonb_agg(jsonb_build_object(
    'question',p.question,'ends_at',p.ends_at,'archived_at',p.archived_at,
    'expires_at',p.archived_at+interval '30 days',
    'votes',(SELECT count(*) FROM public.poll_votes v WHERE v.poll_id=p.id)
  ) ORDER BY p.ends_at DESC) FROM (SELECT * FROM public.polls WHERE archived_at IS NOT NULL ORDER BY ends_at DESC LIMIT 150)p),'[]'::jsonb),
  'announcements',coalesce((SELECT jsonb_agg(jsonb_build_object(
    'title',a.title,'body',a.body,'created_at',a.created_at,
    'archived_at',a.archived_at,'expires_at',a.archived_at+interval '30 days'
  ) ORDER BY a.created_at DESC) FROM (SELECT * FROM public.screen_announcements WHERE archived_at IS NOT NULL ORDER BY created_at DESC LIMIT 150)a),'[]'::jsonb),
  'messages',coalesce((SELECT jsonb_agg(jsonb_build_object(
    'body',m.body,'type',m.type,'created_at',m.created_at,'archived_at',m.archived_at,
    'expires_at',m.archived_at+interval '30 days',
    'author',coalesce(p.name,'Usuário')
  ) ORDER BY m.created_at DESC)
  FROM (SELECT * FROM public.messages WHERE archived_at IS NOT NULL AND
    (public.is_developer() OR user_id=auth.uid()) ORDER BY created_at DESC LIMIT 150)m
  LEFT JOIN public.profiles p ON p.id=m.user_id),'[]'::jsonb),
  'support',coalesce((SELECT jsonb_agg(jsonb_build_object(
    'protocol',t.protocol,'category',t.category,'target_role',t.target_role,
    'closed_at',t.closed_at,'archived_at',t.archived_at,
    'expires_at',t.archived_at+interval '30 days',
    'messages',(SELECT coalesce(jsonb_agg(jsonb_build_object(
       'body',sm.body,'created_at',sm.created_at,
       'author',coalesce(pr.name,'Usuário')) ORDER BY sm.created_at),'[]'::jsonb)
       FROM public.support_chat_messages sm LEFT JOIN public.profiles pr ON pr.id=sm.sender_id
       WHERE sm.ticket_id=t.id)
  ) ORDER BY t.closed_at DESC) FROM (SELECT * FROM public.support_tickets WHERE archived_at IS NOT NULL AND
    (public.is_developer() OR requester_id=auth.uid()) ORDER BY closed_at DESC LIMIT 100)t),'[]'::jsonb)
 );
END $function$;

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
 WHERE archived_at IS NULL AND ends_at<=now()-interval '30 days';
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
  WHERE p.archived_at IS NULL AND (v_coord OR (r.role='coroinha' AND p.starts_at<=now()))
 ),'[]'::jsonb);
END $function$;

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
 PERFORM public.archive_maintenance();
 RETURN v_poll||jsonb_build_object('autoApprovals',v_approved);
END $function$;

CREATE OR REPLACE FUNCTION public.support_coord_list()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_user uuid:=auth.uid();v_manager boolean;
BEGIN
 IF v_user IS NULL OR NOT public.is_approved() THEN RAISE EXCEPTION 'Acesso não autorizado' USING ERRCODE='42501'; END IF;
 SELECT EXISTS(SELECT 1 FROM public.profiles WHERE id=v_user AND approved AND role='coordenadora') INTO v_manager;
 RETURN coalesce((
  SELECT jsonb_agg(jsonb_build_object(
   'id',t.id,'protocol',t.protocol,'category',t.category,'status',t.status,
   'requester_name',p.name,'requester_email',p.email,
   'created_at',t.created_at,'updated_at',t.updated_at,'closed_at',t.closed_at,
   'message_count',(SELECT count(*) FROM public.support_chat_messages m WHERE m.ticket_id=t.id),
   'last_message',(SELECT left(m.body,140) FROM public.support_chat_messages m WHERE m.ticket_id=t.id ORDER BY m.created_at DESC,m.id DESC LIMIT 1)
  ) ORDER BY (t.status='aberto') DESC,t.updated_at DESC)
  FROM public.support_tickets t JOIN public.profiles p ON p.id=t.requester_id
  WHERE t.archived_at IS NULL AND t.target_role='coordenadora'
    AND (v_manager OR (t.requester_id=v_user AND t.status='aberto'))
 ),'[]'::jsonb);
END $function$;

CREATE OR REPLACE FUNCTION public.support_coord_messages(p_ticket uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_user uuid:=auth.uid();v_manager boolean;v_ticket public.support_tickets%ROWTYPE;
BEGIN
 IF v_user IS NULL OR NOT public.is_approved() THEN RAISE EXCEPTION 'Acesso não autorizado' USING ERRCODE='42501'; END IF;
 SELECT EXISTS(SELECT 1 FROM public.profiles WHERE id=v_user AND approved AND role='coordenadora') INTO v_manager;
 SELECT * INTO v_ticket FROM public.support_tickets WHERE id=p_ticket;
 IF NOT FOUND OR v_ticket.archived_at IS NOT NULL OR v_ticket.target_role<>'coordenadora' OR (NOT v_manager AND (v_ticket.requester_id<>v_user OR v_ticket.status<>'aberto')) THEN
  RAISE EXCEPTION 'Atendimento não encontrado' USING ERRCODE='42501'; END IF;
 RETURN coalesce((
  SELECT jsonb_agg(jsonb_build_object(
   'id',m.id,'body',m.body,'sender_id',m.sender_id,
   'sender_name',coalesce(p.name,'Usuário'),'developer',p.role='coordenadora',
   'created_at',m.created_at
  ) ORDER BY m.created_at,m.id)
  FROM public.support_chat_messages m JOIN public.profiles p ON p.id=m.sender_id
  WHERE m.ticket_id=p_ticket
 ),'[]'::jsonb);
END $function$;

CREATE OR REPLACE FUNCTION public.support_list()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_user uuid:=auth.uid();v_dev boolean;
BEGIN
 IF v_user IS NULL OR NOT public.is_approved() THEN RAISE EXCEPTION 'Acesso não autorizado' USING ERRCODE='42501'; END IF;
 v_dev:=public.is_developer();
 RETURN coalesce((
  SELECT jsonb_agg(jsonb_build_object(
   'id',t.id,'protocol',t.protocol,'category',t.category,'status',t.status,
   'requester_name',p.name,'requester_email',p.email,
   'created_at',t.created_at,'updated_at',t.updated_at,'closed_at',t.closed_at,
   'message_count',(SELECT count(*) FROM public.support_chat_messages m WHERE m.ticket_id=t.id),
   'last_message',(SELECT left(m.body,140) FROM public.support_chat_messages m WHERE m.ticket_id=t.id ORDER BY m.created_at DESC,m.id DESC LIMIT 1)
  ) ORDER BY (t.status='aberto') DESC,t.updated_at DESC)
  FROM public.support_tickets t JOIN public.profiles p ON p.id=t.requester_id
  WHERE t.archived_at IS NULL AND t.target_role='desenvolvedor' AND (v_dev OR t.requester_id=v_user) AND (v_dev OR t.status='aberto')
 ),'[]'::jsonb);
END $function$;

CREATE OR REPLACE FUNCTION public.support_messages(p_ticket uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_user uuid:=auth.uid();v_dev boolean;v_ticket public.support_tickets%ROWTYPE;
BEGIN
 IF v_user IS NULL OR NOT public.is_approved() THEN RAISE EXCEPTION 'Acesso não autorizado' USING ERRCODE='42501'; END IF;
 v_dev:=public.is_developer();
 SELECT * INTO v_ticket FROM public.support_tickets WHERE id=p_ticket;
 IF NOT FOUND OR v_ticket.archived_at IS NOT NULL OR v_ticket.target_role<>'desenvolvedor' OR (NOT v_dev AND (v_ticket.requester_id<>v_user OR v_ticket.status<>'aberto')) THEN
  RAISE EXCEPTION 'Atendimento não encontrado' USING ERRCODE='42501';
 END IF;
 RETURN coalesce((
  SELECT jsonb_agg(jsonb_build_object(
   'id',m.id,'body',m.body,'sender_id',m.sender_id,
   'sender_name',coalesce(p.name,'Usuário'),'developer',p.role='desenvolvedor',
   'created_at',m.created_at
  ) ORDER BY m.created_at,m.id)
  FROM public.support_chat_messages m JOIN public.profiles p ON p.id=m.sender_id
  WHERE m.ticket_id=p_ticket
 ),'[]'::jsonb);
END $function$;

ALTER POLICY "assignment_manage" ON public."assignments" USING ((can_manage_service_group(service_group) AND (EXISTS ( SELECT 1
   FROM masses m
  WHERE ((m.id = assignments.mass_id) AND (m.archived_at IS NULL) AND (m.starts_at > (now() - '24:00:00'::interval))))))) WITH CHECK ((can_manage_service_group(service_group) AND (EXISTS ( SELECT 1
   FROM masses m
  WHERE ((m.id = assignments.mass_id) AND (m.archived_at IS NULL) AND (m.starts_at > (now() - '24:00:00'::interval)))))));
ALTER POLICY "assignment_read" ON public."assignments" USING (((is_developer() OR (is_approved() AND has_site_permission('view_scales'::text) AND ((NOT (EXISTS ( SELECT 1
   FROM profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'pai'::text))))) OR has_site_permission('view_child_scales'::text)))) AND (EXISTS ( SELECT 1
   FROM masses m
  WHERE ((m.id = assignments.mass_id) AND m.published AND (m.archived_at IS NULL) AND (m.starts_at > (now() - '24:00:00'::interval)))))));
ALTER POLICY "mass_delete" ON public."masses" USING (((archived_at IS NULL) AND (starts_at > (now() - '24:00:00'::interval)) AND has_site_permission('delete_scales'::text) AND (is_developer() OR (NOT (EXISTS ( SELECT 1
   FROM assignments a
  WHERE ((a.mass_id = masses.id) AND (NOT can_manage_service_group(a.service_group)))))))));
ALTER POLICY "mass_read" ON public."masses" USING (((archived_at IS NULL) AND (starts_at > (now() - '24:00:00'::interval)) AND (is_developer() OR (is_approved() AND has_site_permission('view_scales'::text) AND ((NOT (EXISTS ( SELECT 1
   FROM profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'pai'::text))))) OR has_site_permission('view_child_scales'::text)) AND published))));
ALTER POLICY "mass_update" ON public."masses" USING (((archived_at IS NULL) AND (starts_at > (now() - '24:00:00'::interval)) AND (is_developer() OR (has_site_permission('create_scales'::text) AND (NOT (EXISTS ( SELECT 1
   FROM assignments a
  WHERE ((a.mass_id = masses.id) AND (NOT can_manage_service_group(a.service_group)))))))))) WITH CHECK (((archived_at IS NULL) AND (starts_at > (now() - '24:00:00'::interval)) AND (is_developer() OR (has_site_permission('create_scales'::text) AND (NOT (EXISTS ( SELECT 1
   FROM assignments a
  WHERE ((a.mass_id = masses.id) AND (NOT can_manage_service_group(a.service_group))))))))));
ALTER POLICY "messages_read" ON public."messages" USING (((archived_at IS NULL) AND (is_coordinator() OR (user_id = auth.uid()))));
ALTER POLICY "notes_read" ON public."notifications" USING (((archived_at IS NULL) AND (((user_id = auth.uid()) AND has_site_permission('read_notifications'::text)) OR has_site_permission('send_notifications'::text))));
ALTER POLICY "notes_update" ON public."notifications" USING (((archived_at IS NULL) AND (user_id = auth.uid()))) WITH CHECK (((archived_at IS NULL) AND (user_id = auth.uid())));
ALTER POLICY "requests_manage" ON public."requests" USING (((EXISTS ( SELECT 1
   FROM masses m
  WHERE ((m.id = requests.mass_id) AND (m.archived_at IS NULL) AND (m.starts_at > (now() - '24:00:00'::interval))))) AND has_site_permission('approve_requests'::text) AND can_manage_service_group(service_group))) WITH CHECK (((EXISTS ( SELECT 1
   FROM masses m
  WHERE ((m.id = requests.mass_id) AND (m.archived_at IS NULL) AND (m.starts_at > (now() - '24:00:00'::interval))))) AND has_site_permission('approve_requests'::text) AND can_manage_service_group(service_group)));
ALTER POLICY "requests_read" ON public."requests" USING (((EXISTS ( SELECT 1
   FROM masses m
  WHERE ((m.id = requests.mass_id) AND (m.archived_at IS NULL) AND (m.starts_at > (now() - '24:00:00'::interval))))) AND (can_manage_service_group(service_group) OR (user_id = auth.uid()))));
ALTER POLICY "screen_announcement_read" ON public."screen_announcements" USING (((archived_at IS NULL) AND (has_site_permission('send_popup'::text) OR (EXISTS ( SELECT 1
   FROM profiles me
  WHERE ((me.id = auth.uid()) AND me.approved AND screen_announcements.active AND ((screen_announcements.target_role = 'all'::text) OR ((screen_announcements.target_role = 'individual'::text) AND (screen_announcements.target_user_id = me.id)) OR (screen_announcements.target_role = me.role))))))));
ALTER POLICY "screen_announcement_update" ON public."screen_announcements" USING (((archived_at IS NULL) AND has_site_permission('send_popup'::text))) WITH CHECK (((archived_at IS NULL) AND has_site_permission('send_popup'::text)));
REVOKE ALL ON FUNCTION public.archive_list(),public.archive_maintenance() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.archive_list() TO coroinhas_app,coroinhas_gateway;
