-- 045 — Centro completo de permissões / automações
-- Prerequisitos: migration/sql/044-developer-permissions.sql e esquema Neon atual.
-- Idempotente para reexecução em homologação. Não modifica contas ou escalas existentes.
CREATE TABLE IF NOT EXISTS public.permission_catalog(key text PRIMARY KEY, category text NOT NULL,label text NOT NULL,default_roles text[] NOT NULL DEFAULT '{}'::text[],sensitive boolean NOT NULL DEFAULT false);
INSERT INTO public.permission_catalog(key,category,label,default_roles,sensitive) VALUES
('approve_requests','Coordenação','Aprovar solicitações de serviço',ARRAY['coordenadora']::text[],true),
('attendance','Coordenação','Registrar presença ou falta',ARRAY['coordenadora']::text[],true),
('confirm_assignment','Coroinhas e cerimoniários','Confirmar minha escala',ARRAY['coroinha','cerimoniario']::text[],false),
('create_scales','Coordenação','Cadastrar missas e escalas',ARRAY['coordenadora']::text[],true),
('delete_scales','Coordenação','Excluir escalas',ARRAY['coordenadora']::text[],true),
('edit_cerimoniario','Coordenação','Editar funções e vagas dos cerimoniários',ARRAY['coordenadora_cerimoniario']::text[],true),
('edit_coroinha','Coordenação','Editar funções e vagas dos coroinhas',ARRAY['coordenadora_coroinha']::text[],true),
('manage_fixed_rules','Coordenação','Gerenciar escala automática de integrantes fixos',ARRAY['coordenadora']::text[],true),
('manage_guides','Coordenação','Gerenciar orientações e funções',ARRAY['coordenadora']::text[],true),
('manage_polls','Coordenação','Criar e editar enquetes',ARRAY['coordenadora']::text[],true),
('manage_users','Desenvolvedor','Gerenciar contas e funções',ARRAY['desenvolvedor']::text[],true),
('publish_updates','Desenvolvedor','Publicar e editar atualizações',ARRAY['desenvolvedor']::text[],true),
('read_notifications','Coroinhas e cerimoniários','Consultar notificações',ARRAY['coroinha','cerimoniario','coordenadora','pai','desenvolvedor']::text[],false),
('request_service','Coroinhas e cerimoniários','Solicitar vaga para servir',ARRAY['coroinha','cerimoniario']::text[],false),
('send_notifications','Coordenação','Enviar notificações',ARRAY['coordenadora']::text[],true),
('send_popup','Desenvolvedor','Publicar avisos pop-up',ARRAY['desenvolvedor']::text[],true),
('send_suggestions','Coroinhas e cerimoniários','Enviar sugestões e reclamações',ARRAY['coroinha','cerimoniario']::text[],false),
('unassign_self','Coroinhas e cerimoniários','Desmarcar minha escala',ARRAY['coroinha','cerimoniario']::text[],false),
('view_audit','Desenvolvedor','Visualizar auditoria',ARRAY['desenvolvedor']::text[],true),
('view_child_scales','Pais e responsáveis','Acompanhar escalas vinculadas',ARRAY['pai']::text[],false),
('view_developer_panel','Desenvolvedor','Consultar painel do desenvolvedor',ARRAY['desenvolvedor']::text[],true),
('view_reports','Coordenação','Consultar relatórios',ARRAY['coordenadora']::text[],false),
('view_scales','Coroinhas e cerimoniários','Visualizar escalas',ARRAY['coroinha','cerimoniario','coordenadora','pai','desenvolvedor']::text[],false),
('vote_polls','Coroinhas e cerimoniários','Responder enquetes',ARRAY['coroinha']::text[],false)
ON CONFLICT(key) DO UPDATE SET category=EXCLUDED.category,label=EXCLUDED.label,default_roles=EXCLUDED.default_roles,sensitive=EXCLUDED.sensitive;
ALTER TABLE public.permission_rules DROP CONSTRAINT IF EXISTS permission_rules_permission_key_check;
DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conname='permission_rules_catalog_fkey' AND conrelid='public.permission_rules'::regclass) THEN ALTER TABLE public.permission_rules ADD CONSTRAINT permission_rules_catalog_fkey FOREIGN KEY(permission_key) REFERENCES public.permission_catalog(key); END IF; END $$;
CREATE TABLE IF NOT EXISTS public.automation_catalog(key text PRIMARY KEY,label text NOT NULL,description text NOT NULL,implemented boolean NOT NULL DEFAULT true);
INSERT INTO public.automation_catalog(key,label,description,implemented) VALUES
('auto_approval_3h','Aprovação de vagas nas últimas 3 horas','Aprova pedidos elegíveis quando a missa está próxima',true),
('notify_assignment_events','Avisos de escalas e presenças','Notifica integrantes e coordenação após mudanças nas escalas',true),
('notify_coordinator_messages','Avisos de mensagens','Notifica coordenação sobre sugestões e reclamações',true),
('notify_profile_approved','Avisos de cadastro aprovado','Notifica usuários quando seus cadastros são aprovados',true),
('notify_profile_pending','Avisos de cadastro pendente','Notifica a coordenação de novos cadastros',true),
('notify_service_requests','Avisos de solicitações','Notifica a coordenação quando alguém solicita uma vaga',true),
('poll_dispatch','Avisos automáticos de enquetes','Notifica abertura, lembrete e encerramento das enquetes',true),
('push_queue','Enfileiramento de notificações push','Envia avisos para a fila de notificações do dispositivo',true)
ON CONFLICT(key) DO UPDATE SET label=EXCLUDED.label,description=EXCLUDED.description,implemented=EXCLUDED.implemented;
INSERT INTO public.service_settings(key,enabled,updated_at) SELECT key,true,now() FROM public.automation_catalog WHERE key<>'auto_approval_3h' ON CONFLICT(key) DO NOTHING;

CREATE OR REPLACE FUNCTION migration_private.queue_push_notice()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE active boolean;
BEGIN
 IF NOT public.automation_enabled('push_queue') THEN RETURN NEW; END IF;

 SELECT enabled AND activated_at IS NOT NULL AND
        NEW.created_at>=activated_at INTO active
 FROM migration_private.push_runtime WHERE id;
 INSERT INTO migration_private.push_outbox(notification_id,state)
 VALUES(NEW.id,CASE WHEN coalesce(active,false) THEN 'pending' ELSE 'suppressed' END)
 ON CONFLICT DO NOTHING;
 RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION public.approve_service_request(p_request_id uuid, p_assignment_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE r public.requests%rowtype; a public.assignments%rowtype; v_time timestamptz; v_name text;
BEGIN
 IF NOT public.has_site_permission('approve_requests') THEN RAISE EXCEPTION 'Sem permissão para esta ação' USING ERRCODE='42501'; END IF;

 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Acesso negado' USING errcode='42501'; END IF;
 SELECT * INTO r FROM public.requests WHERE id=p_request_id FOR UPDATE;
 IF NOT FOUND OR r.status<>'pendente' THEN RAISE EXCEPTION 'Pedido não está pendente'; END IF;
 IF NOT public.can_manage_service_group(r.service_group) THEN RAISE EXCEPTION 'Coordenação de outro grupo' USING errcode='42501'; END IF;
 SELECT * INTO a FROM public.assignments WHERE id=p_assignment_id FOR UPDATE;
 IF NOT FOUND OR a.mass_id<>r.mass_id OR a.service_group<>r.service_group THEN RAISE EXCEPTION 'Vaga incompatível com a solicitação'; END IF;
 SELECT starts_at INTO v_time FROM public.masses WHERE id=r.mass_id;
 IF v_time IS NULL OR v_time<=now() THEN RAISE EXCEPTION 'Missa já iniciada'; END IF;
 IF a.server_id IS NOT NULL AND a.status<>'desmarcado' THEN RAISE EXCEPTION 'Vaga ocupada'; END IF;
 IF r.type='substituir' AND (r.assignment_id IS DISTINCT FROM a.id OR a.status<>'desmarcado') THEN RAISE EXCEPTION 'Vaga de substituição inválida'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.profiles p WHERE p.id=r.user_id AND p.approved AND p.role=r.service_group) THEN
  RAISE EXCEPTION 'Cadastro incompatível com a vaga' USING errcode='42501';
 END IF;
 IF EXISTS(SELECT 1 FROM public.assignments x WHERE x.mass_id=r.mass_id AND x.server_id=r.user_id AND x.status<>'desmarcado' AND x.id<>a.id) THEN
  RAISE EXCEPTION 'Integrante já escalado';
 END IF;
 UPDATE public.assignments SET server_id=r.user_id,status='escalado',reason=NULL WHERE id=a.id;
 UPDATE public.requests SET status='aprovado' WHERE id=r.id;
 SELECT name INTO v_name FROM public.profiles WHERE id=r.user_id;
 INSERT INTO public.notifications(user_id,title,body,event_key) VALUES
 (r.user_id,'Você foi escalado!', 'Você foi escalado para servir em '||to_char(v_time AT TIME ZONE 'America/Sao_Paulo','DD/MM/YYYY HH24:MI')||' na função '||a.function_name||'.','service_approved');
END $function$;

CREATE OR REPLACE FUNCTION public.automation_enabled(p_key text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$ SELECT coalesce((SELECT s.enabled FROM public.service_settings s WHERE s.key=p_key AND EXISTS(SELECT 1 FROM public.automation_catalog c WHERE c.key=p_key)),false) $function$;

CREATE OR REPLACE FUNCTION public.can_manage_service_group(p_group text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$ SELECT CASE WHEN p_group='coroinha' THEN public.has_site_permission('edit_coroinha') WHEN p_group='cerimoniario' THEN public.has_site_permission('edit_cerimoniario') ELSE false END $function$;

CREATE OR REPLACE FUNCTION public.create_mass_with_assignments(p_title text, p_starts_at timestamp with time zone, p_location text, p_celebrant text, p_notes text, p_roles jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_user uuid:=auth.uid();v_mass uuid;v_count int;v_item jsonb;v_fn text;v_server uuid;v_group text;
BEGIN
 IF NOT public.has_site_permission('create_scales') THEN RAISE EXCEPTION 'Sem permissão para esta ação' USING ERRCODE='42501'; END IF;

 IF NOT public.is_coordinator() THEN
  RAISE EXCEPTION 'Somente a coordenação pode cadastrar missas' USING ERRCODE='42501';
 END IF;
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

CREATE OR REPLACE FUNCTION public.developer_apply_automations(p_changes jsonb, p_confirmation text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE x jsonb; n int:=0;
BEGIN
 IF NOT public.is_developer() OR trim(coalesce(p_confirmation,''))<>'DESENVOLVEDOR' THEN RAISE EXCEPTION 'Confirmação inválida' USING ERRCODE='42501'; END IF;
 IF jsonb_typeof(p_changes)<>'array' OR jsonb_array_length(p_changes)>30 THEN RAISE EXCEPTION 'Alterações inválidas' USING ERRCODE='22023'; END IF;
 FOR x IN SELECT value FROM jsonb_array_elements(p_changes) LOOP
  IF jsonb_typeof(x->'enabled')<>'boolean' OR NOT EXISTS(SELECT 1 FROM public.automation_catalog WHERE key=x->>'key' AND implemented) THEN RAISE EXCEPTION 'Automação inválida' USING ERRCODE='22023'; END IF;
  INSERT INTO public.service_settings(key,enabled,updated_at) VALUES(x->>'key',(x->>'enabled')::boolean,now()) ON CONFLICT(key) DO UPDATE SET enabled=EXCLUDED.enabled,updated_at=now();
  n:=n+1;
 END LOOP;
 RETURN n;
END $function$;

CREATE OR REPLACE FUNCTION public.developer_apply_permissions(p_user uuid, p_changes jsonb, p_until timestamp with time zone, p_confirmation text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE x jsonb; v_n integer:=0;
BEGIN
 IF NOT public.is_developer() OR trim(coalesce(p_confirmation,''))<>'DESENVOLVEDOR' THEN RAISE EXCEPTION 'Confirmação de desenvolvedor inválida' USING ERRCODE='42501'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.profiles WHERE id=p_user AND role<>'desenvolvedor') THEN RAISE EXCEPTION 'Conta protegida' USING ERRCODE='42501'; END IF;
 IF jsonb_typeof(p_changes)<>'array' OR jsonb_array_length(p_changes)>50 THEN RAISE EXCEPTION 'Alterações inválidas' USING ERRCODE='22023'; END IF;
 IF p_until IS NOT NULL AND (p_until<=now() OR p_until>now()+interval '365 days') THEN RAISE EXCEPTION 'Prazo inválido' USING ERRCODE='22023'; END IF;
 FOR x IN SELECT value FROM jsonb_array_elements(p_changes) LOOP
  IF jsonb_typeof(x)<>'object' OR jsonb_typeof(x->'allowed')<>'boolean' OR NOT EXISTS(SELECT 1 FROM public.permission_catalog WHERE key=x->>'key') THEN RAISE EXCEPTION 'Função desconhecida' USING ERRCODE='22023'; END IF;
  INSERT INTO public.permission_rules(subject_user,permission_key,allowed,expires_at,created_by) VALUES(p_user,x->>'key',(x->>'allowed')::boolean,p_until,auth.uid());
  v_n:=v_n+1;
 END LOOP;
 RETURN v_n;
END $function$;

CREATE OR REPLACE FUNCTION public.developer_audit_recent()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
 IF NOT public.has_site_permission('view_audit') THEN RAISE EXCEPTION 'Sem permissão para consultar auditoria' USING ERRCODE='42501'; END IF;
 RETURN COALESCE((SELECT jsonb_agg(to_jsonb(a) ORDER BY a.happened_at DESC,a.id DESC)
 FROM (SELECT id,happened_at,actor_email,table_name,action,before_data,after_data FROM public.audit_log ORDER BY happened_at DESC,id DESC LIMIT 250) a),'[]'::jsonb);
END $function$;

CREATE OR REPLACE FUNCTION public.developer_automation_snapshot()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$ BEGIN IF NOT public.is_developer() THEN RAISE EXCEPTION 'Acesso restrito' USING ERRCODE='42501'; END IF; RETURN coalesce((SELECT jsonb_agg(jsonb_build_object('key',a.key,'label',a.label,'description',a.description,'enabled',coalesce(s.enabled,false),'implemented',a.implemented) ORDER BY a.label) FROM public.automation_catalog a LEFT JOIN public.service_settings s ON s.key=a.key),'[]'::jsonb); END $function$;

CREATE OR REPLACE FUNCTION public.developer_manage_user(p_user uuid, p_action text, p_role text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_email text;
BEGIN
 IF NOT public.has_site_permission('manage_users') THEN RAISE EXCEPTION 'Sem permissão para esta ação' USING ERRCODE='42501'; END IF;

 IF NOT public.has_site_permission('manage_users') OR auth.uid() IS NULL THEN RAISE EXCEPTION 'Acesso restrito ao desenvolvedor' USING ERRCODE='42501'; END IF;
 IF NOT public.is_developer() AND (p_role='desenvolvedor' OR EXISTS(SELECT 1 FROM public.profiles WHERE id=p_user AND role='desenvolvedor')) THEN RAISE EXCEPTION 'Acesso privilegiado reservado' USING ERRCODE='42501'; END IF;
 IF p_user=auth.uid() THEN RAISE EXCEPTION 'Não é permitido alterar sua própria conta';END IF;
 SELECT email INTO v_email FROM public.profiles WHERE id=p_user FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Usuário não encontrado';END IF;
 IF p_action='role' THEN
  IF p_role IS NULL OR p_role NOT IN ('coroinha','cerimoniario','pai','coordenadora','coordenadora_cerimoniario','desenvolvedor') THEN RAISE EXCEPTION 'Perfil inválido';END IF;
  UPDATE public.profiles SET role=CASE WHEN p_role='coordenadora_cerimoniario' THEN 'coordenadora' ELSE p_role END, coordination_group=CASE WHEN p_role='coordenadora_cerimoniario' THEN 'cerimoniario' ELSE 'coroinha' END,approved=true WHERE id=p_user;
  UPDATE neon_auth.session SET "expiresAt"=now() WHERE "userId" IN (SELECT id FROM neon_auth."user" WHERE id::text IN (SELECT subject FROM migration_private.identity_map WHERE provider='neon' AND profile_id=p_user)) AND "expiresAt">now();
  RETURN 'Perfil atualizado';
 ELSIF p_action='ban' THEN
  INSERT INTO public.banned_emails(email,banned_by) VALUES(lower(v_email),auth.uid()) ON CONFLICT DO NOTHING;
  UPDATE neon_auth."user" SET banned=true WHERE id::text IN(SELECT subject FROM migration_private.identity_map WHERE provider='neon' AND profile_id=p_user);
  -- Expire all active Neon sessions of the blocked identity without deleting history.
  UPDATE neon_auth.session
  SET "expiresAt"=now(), "updatedAt"=now()
  WHERE "userId" IN (
    SELECT id FROM neon_auth."user" WHERE id::text IN (
      SELECT subject FROM migration_private.identity_map WHERE provider='neon' AND profile_id=p_user
    )
  ) AND "expiresAt">now();
  UPDATE public.profiles SET approved=false WHERE id=p_user;
  UPDATE neon_auth.session SET "expiresAt"=now() WHERE "userId" IN (SELECT id FROM neon_auth."user" WHERE id::text IN (SELECT subject FROM migration_private.identity_map WHERE provider='neon' AND profile_id=p_user)) AND "expiresAt">now();
  RETURN 'Conta bloqueada';
 ELSIF p_action='delete' THEN
  RAISE EXCEPTION 'Exclusão desativada durante a migração: nenhum registro será apagado';
 ELSE RAISE EXCEPTION 'Ação inválida';END IF;
END $function$;

CREATE OR REPLACE FUNCTION public.developer_permission_snapshot(p_user uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE p public.profiles%rowtype;
BEGIN
 IF NOT public.is_developer() THEN RAISE EXCEPTION 'Acesso restrito' USING ERRCODE='42501'; END IF;
 SELECT * INTO p FROM public.profiles WHERE id=p_user;
 IF NOT FOUND THEN RAISE EXCEPTION 'Usuário inexistente' USING ERRCODE='22023'; END IF;
 RETURN coalesce((SELECT jsonb_agg(jsonb_build_object('key',c.key,'category',c.category,'label',c.label,
  'enabled',coalesce((SELECT x.allowed FROM public.permission_rules x WHERE x.subject_user=p.id AND x.permission_key=c.key AND (x.expires_at IS NULL OR x.expires_at>now()) ORDER BY x.created_at DESC,x.id DESC LIMIT 1),
  (SELECT x.allowed FROM public.permission_rules x WHERE x.subject_role=(CASE WHEN p.role='coordenadora' THEN 'coordenadora_'||coalesce(p.coordination_group,'coroinha') ELSE p.role END) AND x.permission_key=c.key AND (x.expires_at IS NULL OR x.expires_at>now()) ORDER BY x.created_at DESC,x.id DESC LIMIT 1),
  (SELECT x.allowed FROM public.permission_rules x WHERE x.subject_role=p.role AND x.permission_key=c.key AND (x.expires_at IS NULL OR x.expires_at>now()) ORDER BY x.created_at DESC,x.id DESC LIMIT 1),
  p.role='desenvolvedor' OR p.role=ANY(c.default_roles) OR (p.role='coordenadora' AND ('coordenadora_'||coalesce(p.coordination_group,'coroinha'))=ANY(c.default_roles))),
  'default',p.role='desenvolvedor' OR p.role=ANY(c.default_roles) OR (p.role='coordenadora' AND ('coordenadora_'||coalesce(p.coordination_group,'coroinha'))=ANY(c.default_roles)),
  'sensitive',c.sensitive) ORDER BY c.category,c.label) FROM public.permission_catalog c),'[]'::jsonb);
END $function$;

CREATE OR REPLACE FUNCTION public.developer_recent_access(p_role text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
 IF NOT public.has_site_permission('view_developer_panel') THEN RAISE EXCEPTION 'Sem permissão para esta ação' USING ERRCODE='42501'; END IF;

 IF NOT public.is_developer() THEN RAISE EXCEPTION 'Sem acesso' USING ERRCODE='42501'; END IF;
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

CREATE OR REPLACE FUNCTION public.developer_revoke_permission(p_id uuid, p_confirmation text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
 IF NOT public.is_developer() OR trim(coalesce(p_confirmation,''))<>'DESENVOLVEDOR' THEN RAISE EXCEPTION 'Confirmação inválida' USING ERRCODE='42501'; END IF;
 DELETE FROM public.permission_rules WHERE id=p_id AND subject_user IS NOT NULL AND expires_at IS NOT NULL;
 RETURN FOUND;
END $function$;

CREATE OR REPLACE FUNCTION public.developer_usage_summary()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
 IF NOT public.has_site_permission('view_developer_panel') THEN RAISE EXCEPTION 'Sem permissão para esta ação' USING ERRCODE='42501'; END IF;

 IF NOT public.is_developer() THEN RAISE EXCEPTION 'Sem acesso' USING ERRCODE='42501'; END IF;
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

CREATE OR REPLACE FUNCTION public.has_site_permission(p_key text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE p public.profiles%rowtype; c public.permission_catalog%rowtype; v_allowed boolean; v_role text;
BEGIN
 SELECT * INTO p FROM public.profiles WHERE id=auth.uid() AND approved;
 IF NOT FOUND THEN RETURN false; END IF;
 IF p.role='desenvolvedor' THEN RETURN true; END IF;
 SELECT * INTO c FROM public.permission_catalog WHERE key=p_key;
 IF NOT FOUND THEN RETURN false; END IF;
 v_role:=CASE WHEN p.role='coordenadora' THEN 'coordenadora_'||coalesce(p.coordination_group,'coroinha') ELSE p.role END;
 SELECT allowed INTO v_allowed FROM public.permission_rules WHERE subject_user=p.id AND permission_key=p_key AND (expires_at IS NULL OR expires_at>now()) ORDER BY created_at DESC,id DESC LIMIT 1;
 IF FOUND THEN RETURN v_allowed; END IF;
 SELECT allowed INTO v_allowed FROM public.permission_rules WHERE subject_role=v_role AND permission_key=p_key AND (expires_at IS NULL OR expires_at>now()) ORDER BY created_at DESC,id DESC LIMIT 1;
 IF FOUND THEN RETURN v_allowed; END IF;
 SELECT allowed INTO v_allowed FROM public.permission_rules WHERE subject_role=p.role AND permission_key=p_key AND (expires_at IS NULL OR expires_at>now()) ORDER BY created_at DESC,id DESC LIMIT 1;
 IF FOUND THEN RETURN v_allowed; END IF;
 RETURN p.role=ANY(c.default_roles) OR v_role=ANY(c.default_roles);
END $function$;

CREATE OR REPLACE FUNCTION public.my_site_permissions()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
 IF auth.uid() IS NULL OR NOT public.is_approved() THEN RETURN '{}'::jsonb; END IF;
 RETURN coalesce((SELECT jsonb_object_agg(key,public.has_site_permission(key)) FROM public.permission_catalog),'{}'::jsonb);
END $function$;

CREATE OR REPLACE FUNCTION public.notify_approved_profile()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
 IF NOT public.automation_enabled('notify_profile_approved') THEN RETURN NEW; END IF;

 IF OLD.approved IS FALSE AND NEW.approved IS TRUE AND NEW.role='coroinha' THEN
  INSERT INTO public.notifications(user_id,title,body,event_key)
  VALUES(NEW.id,'Cadastro aprovado','Seu acesso ao Coroinhas foi aprovado. Bem-vindo(a)!','server_approval');
 END IF;
 RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION public.notify_assignment_events()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_mass public.masses%rowtype; v_name text;
BEGIN
 IF NOT public.automation_enabled('notify_assignment_events') THEN RETURN NEW; END IF;

 SELECT * INTO v_mass FROM public.masses WHERE id=NEW.mass_id;
 IF NOT FOUND OR NOT v_mass.published THEN RETURN NEW; END IF;
 SELECT coalesce(nullif(trim(name),''),'Integrante') INTO v_name FROM public.profiles WHERE id=NEW.server_id;
 IF NEW.server_id IS NOT NULL AND NEW.status NOT IN ('desmarcado','faltou')
 AND (TG_OP='INSERT' OR OLD.server_id IS DISTINCT FROM NEW.server_id) THEN
 INSERT INTO public.notifications(user_id,title,body,event_key)
 SELECT p.id,'Você foi escalado(a)',
 'Você está na escala de '||v_mass.title||' em '||to_char(v_mass.starts_at AT TIME ZONE 'America/Sao_Paulo','DD/MM/YYYY "às" HH24:MI')||'.',
 'server_assignments'
 FROM public.profiles p WHERE p.id=NEW.server_id AND p.approved AND p.role=NEW.service_group;
 END IF;
 IF TG_OP='UPDATE' AND OLD.status IS DISTINCT FROM NEW.status
 AND NEW.status IN ('confirmado','desmarcado') AND NEW.server_id IS NOT NULL THEN
 INSERT INTO public.notifications(user_id,title,body,event_key)
 SELECT p.id, CASE WHEN NEW.status='confirmado' THEN 'Escala confirmada' ELSE 'Escala desmarcada' END,
 coalesce(v_name,'Integrante')||CASE WHEN NEW.status='confirmado' THEN ' confirmou participação em ' ELSE ' desmarcou a escala de ' END||v_mass.title||'.',
 'coord_responses'
 FROM public.profiles p WHERE p.approved AND
 (p.role='desenvolvedor' OR (p.role='coordenadora' AND p.coordination_group=NEW.service_group));
 END IF;
 RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION public.notify_coordinator_message()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
 IF NOT public.automation_enabled('notify_coordinator_messages') THEN RETURN NEW; END IF;


 insert into public.notifications(user_id,title,body,event_key)
 select
  p.id,
  case
   when new.type='reclamacao'
   then 'Nova reclamação'
   else 'Nova sugestão'
  end,
  coalesce(
   (
    select name from public.profiles
    where id=new.user_id
   ),
   'Coroinha'
  )||
  ' enviou uma mensagem. Abra Reclamações e Sugestões.', 'coord_messages'

 from public.profiles p
 where p.approved
 and p.role='coordenadora';

 return new;

end;
$function$;

CREATE OR REPLACE FUNCTION public.notify_pending_approval()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
 IF NOT public.automation_enabled('notify_profile_pending') THEN RETURN NEW; END IF;

 if new.approved is false then
  INSERT INTO public.notifications(user_id,title,body,event_key)
  select p.id,'Cadastro aguardando aprovação',
  coalesce(nullif(trim(new.name),''),'Novo usuário') || ' está aguardando aprovação de cadastro.', 'coord_new_accounts'
  from public.profiles p where p.approved=true and p.role='coordenadora' and p.id<>new.id;
 end if;
 return new;
end $function$;

CREATE OR REPLACE FUNCTION public.notify_service_request()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
 DECLARE v_mass public.masses%rowtype;v_name text;
 BEGIN
 IF NOT public.automation_enabled('notify_service_requests') THEN RETURN NEW; END IF;

 SELECT * INTO v_mass FROM public.masses WHERE id=NEW.mass_id;
 SELECT name INTO v_name FROM public.profiles WHERE id=NEW.user_id;
 INSERT INTO public.notifications(user_id,title,body,event_key)
 SELECT p.id,'Nova solicitação para servir',
 coalesce(v_name,'Um integrante')||' solicitou servir em '||
 to_char(v_mass.starts_at AT TIME ZONE 'America/Sao_Paulo','DD/MM/YYYY HH24:MI')||'.','service_request'
 FROM public.profiles p WHERE p.approved AND
 (p.role='desenvolvedor' OR (p.role='coordenadora' AND p.coordination_group=NEW.service_group));
 RETURN NEW;
 END $function$;

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
 IF now()>=v_poll.ends_at THEN RAISE EXCEPTION 'O prazo desta enquete terminou. Não é possível modificar a resposta.' USING ERRCODE='22023'; END IF;
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

 IF NOT public.is_coordinator() THEN RAISE EXCEPTION 'Somente a coordenação pode criar enquetes' USING ERRCODE='42501'; END IF;
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
  INSERT INTO public.notifications(user_id,title,body,event_key,priority,priority_until)
  SELECT id,'Nova enquete disponível',v.question,'polls',v.priority,v.ends_at
  FROM public.profiles WHERE approved AND role='coroinha';
  UPDATE public.polls SET started_notified_at=now() WHERE id=v.id;
  v_open:=v_open+1;
 END LOOP;
 FOR v IN SELECT * FROM public.polls
  WHERE started_notified_at IS NOT NULL AND reminder_notified_at IS NULL
  AND ends_at>now() AND starts_at<=ends_at-interval '24 hours'
  AND now()>=ends_at-interval '24 hours'
  ORDER BY ends_at FOR UPDATE SKIP LOCKED LOOP
  INSERT INTO public.notifications(user_id,title,body,event_key,priority,priority_until)
  SELECT p.id,'Falta 1 dia para encerrar a enquete',v.question||' — responda antes de '||
   to_char(v.ends_at AT TIME ZONE 'America/Sao_Paulo','DD/MM "às" HH24:MI'),
   'polls',v.priority,v.ends_at
  FROM public.profiles p WHERE p.approved AND p.role='coroinha'
  AND NOT EXISTS(SELECT 1 FROM public.poll_votes x WHERE x.poll_id=v.id AND x.user_id=p.id);
  UPDATE public.polls SET reminder_notified_at=now() WHERE id=v.id;
  v_rem:=v_rem+1;
 END LOOP;
 FOR v IN SELECT * FROM public.polls
  WHERE ends_at<=now() AND closed_notified_at IS NULL
  ORDER BY ends_at FOR UPDATE SKIP LOCKED LOOP
  INSERT INTO public.notifications(user_id,title,body,event_key)
  SELECT p.id,'Enquete encerrada','O prazo da enquete foi encerrado.','polls'
  FROM public.profiles p WHERE p.approved AND p.role='coroinha';
  UPDATE public.polls SET closed_notified_at=now() WHERE id=v.id;
  v_closed:=v_closed+1;
 END LOOP;
 RETURN jsonb_build_object('abertas',v_open,'lembretes',v_rem,'encerradas',v_closed);
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

 IF NOT public.is_coordinator() THEN RAISE EXCEPTION 'Somente a coordenação pode editar enquetes' USING ERRCODE='42501'; END IF;
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
 IF now()>=v_poll.ends_at THEN RAISE EXCEPTION 'Esta enquete foi encerrada' USING ERRCODE='22023'; END IF;

 v_count:=cardinality(p_options);
 IF p_options IS NULL OR v_count<1 OR v_count>10 OR (NOT v_poll.multiple_answers AND v_count<>1)
   OR v_count<>(SELECT count(DISTINCT x) FROM unnest(p_options) x)
   OR v_count<>(SELECT count(*) FROM public.poll_options WHERE poll_id=p_poll AND id=ANY(p_options)) THEN
  RAISE EXCEPTION 'Selecione uma opção válida para votar' USING ERRCODE='22023'; END IF;
 DELETE FROM public.poll_votes WHERE poll_id=p_poll AND user_id=v_user;
 INSERT INTO public.poll_votes(poll_id,option_id,user_id) SELECT p_poll,x,v_user FROM unnest(p_options) x;
 RETURN jsonb_build_object('voted',true);
END $function$;

CREATE OR REPLACE FUNCTION public.protect_profile()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
BEGIN
 IF NEW.id IS DISTINCT FROM OLD.id OR NEW.email IS DISTINCT FROM OLD.email OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN RAISE EXCEPTION 'Identidade imutável' USING ERRCODE='42501'; END IF;
 IF (NEW.role IS DISTINCT FROM OLD.role OR NEW.coordination_group IS DISTINCT FROM OLD.coordination_group) AND NOT public.is_developer() THEN RAISE EXCEPTION 'Somente desenvolvedor altera papéis e grupos' USING ERRCODE='42501'; END IF;
 IF (NEW.approved IS DISTINCT FROM OLD.approved OR NEW.notes IS DISTINCT FROM OLD.notes) AND NOT (public.is_coordinator() OR public.has_site_permission('manage_users')) THEN RAISE EXCEPTION 'Sem permissão para administrar cadastros' USING ERRCODE='42501'; END IF;
 IF NOT public.is_developer() AND OLD.role IN ('coordenadora','desenvolvedor') AND NEW.approved IS DISTINCT FROM OLD.approved THEN RAISE EXCEPTION 'Conta administrativa protegida' USING ERRCODE='42501'; END IF;
 RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION public.respond_assignment(p_id uuid, p_action text, p_reason text DEFAULT ''::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v public.assignments%rowtype;
 t timestamptz;
begin
 IF p_action='confirmar' AND NOT public.has_site_permission('confirm_assignment') THEN RAISE EXCEPTION 'Sem permissão para confirmar escala' USING ERRCODE='42501'; END IF;
 IF p_action='desmarcar' AND NOT public.has_site_permission('unassign_self') THEN RAISE EXCEPTION 'Sem permissão para desmarcar escala' USING ERRCODE='42501'; END IF;

 if auth.uid() is null or not public.is_approved() then
  raise exception 'Cadastro aguardando aprovação';
 end if;
 select * into v from public.assignments
 where id=p_id and server_id=auth.uid() for update;
 if not found then
  raise exception 'Escala não encontrada para sua conta';
 end if;
 select starts_at into t from public.masses where id=v.mass_id;
 if t is null then raise exception 'Missa não encontrada'; end if;
 if p_action='desmarcar' then
  if length(trim(coalesce(p_reason,'')))<3 then
   raise exception 'Informe uma justificativa com pelo menos 3 caracteres';
  end if;
  if v.status in ('desmarcado','faltou','presente') then
   raise exception 'Esta escala não permite desistência';
  end if;
  update public.assignments set status='desmarcado',reason=trim(p_reason) where id=p_id;
  if t>now() then
    insert into public.notifications(user_id,title,body,event_key)
    select id,'Vaga para substituição','Função: '||v.function_name||' • '||
       to_char(t at time zone 'America/Sao_Paulo','DD/MM/YYYY HH24:MI'), CASE WHEN role='coordenadora' THEN 'coord_responses' WHEN role='desenvolvedor' THEN 'general' ELSE 'server_substitutes' END
    from public.profiles where approved=true and role IN ('coroinha','coordenadora','desenvolvedor') and id<>auth.uid();
  end if;
 elsif p_action='confirmar' then
  if (t AT TIME ZONE 'America/Sao_Paulo')::date <> (now() AT TIME ZONE 'America/Sao_Paulo')::date
     OR t<=now() then
    raise exception 'Confirmação disponível somente no dia da missa, antes de começar';
  end if;
  if v.status not in ('escalado','confirmado') then
   raise exception 'Esta escala não pode ser confirmada';
  end if;
  update public.assignments set status='confirmado' where id=p_id;
 else
  raise exception 'Ação inválida';
 end if;
end;
$function$;

CREATE OR REPLACE FUNCTION public.send_notification(p_title text, p_body text, p_recipient uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_group uuid:=gen_random_uuid();
BEGIN
 IF NOT public.has_site_permission('send_notifications') THEN RAISE EXCEPTION 'Sem permissão para esta ação' USING ERRCODE='42501'; END IF;

 IF NOT public.is_coordinator() THEN RAISE EXCEPTION 'Acesso negado'; END IF;
 IF length(trim(coalesce(p_title,'')))=0 OR length(trim(coalesce(p_body,'')))=0 THEN RAISE EXCEPTION 'Preencha titulo e mensagem'; END IF;
 INSERT INTO public.notifications(user_id,title,body,group_id,seen,read_at)
 SELECT p.id,trim(p_title),trim(p_body),v_group,false,NULL FROM public.profiles p
 WHERE p.approved=true AND p.role='coroinha' AND (p_recipient IS NULL OR p.id=p_recipient);
 IF NOT FOUND THEN RAISE EXCEPTION 'Nenhum destinatario encontrado'; END IF;
 RETURN v_group;
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

 IF NOT public.is_coordinator() THEN RAISE EXCEPTION 'Acesso negado' USING ERRCODE='42501'; END IF;
 IF coalesce(p_priority,false) AND (p_priority_until IS NULL OR p_priority_until<=now()) THEN
  RAISE EXCEPTION 'Informe um prazo futuro para a notificação prioritária' USING ERRCODE='22023'; END IF;
 v_group:=public.send_notification_targeted(p_title,p_body,p_target,p_recipient);
 IF coalesce(p_priority,false) THEN
  UPDATE public.notifications SET priority=true,priority_until=p_priority_until WHERE group_id=v_group;
 END IF;
 RETURN v_group;
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

 IF NOT public.is_coordinator() THEN RAISE EXCEPTION 'Acesso negado' USING ERRCODE='42501'; END IF;
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
ALTER POLICY "assignment_manage" ON public."assignments" USING (can_manage_service_group(service_group)) WITH CHECK (can_manage_service_group(service_group));
ALTER POLICY "assignment_read" ON public."assignments" USING ((is_developer() OR (is_approved() AND has_site_permission('view_scales'::text) AND ((NOT (EXISTS ( SELECT 1
   FROM profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'pai'::text))))) OR has_site_permission('view_child_scales'::text)) AND (EXISTS ( SELECT 1
   FROM masses m
  WHERE ((m.id = assignments.mass_id) AND m.published))))));
ALTER POLICY "fixed_manage" ON public."fixed_rules" USING (has_site_permission('manage_fixed_rules'::text)) WITH CHECK (has_site_permission('manage_fixed_rules'::text));
ALTER POLICY "fixed_read" ON public."fixed_rules" USING ((is_coordinator() OR (server_id = auth.uid())));
ALTER POLICY "guides_manage" ON public."guides" USING (has_site_permission('manage_guides'::text)) WITH CHECK (has_site_permission('manage_guides'::text));
ALTER POLICY "guides_read" ON public."guides" USING (is_approved());
ALTER POLICY "mass_delete" ON public."masses" USING ((has_site_permission('delete_scales'::text) AND (is_developer() OR (NOT (EXISTS ( SELECT 1
   FROM assignments a
  WHERE ((a.mass_id = masses.id) AND (NOT can_manage_service_group(a.service_group)))))))));
ALTER POLICY "mass_insert" ON public."masses" WITH CHECK (has_site_permission('create_scales'::text));
ALTER POLICY "mass_read" ON public."masses" USING ((is_developer() OR (is_approved() AND has_site_permission('view_scales'::text) AND ((NOT (EXISTS ( SELECT 1
   FROM profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'pai'::text))))) OR has_site_permission('view_child_scales'::text)) AND published)));
ALTER POLICY "mass_update" ON public."masses" USING ((is_developer() OR (has_site_permission('create_scales'::text) AND (NOT (EXISTS ( SELECT 1
   FROM assignments a
  WHERE ((a.mass_id = masses.id) AND (NOT can_manage_service_group(a.service_group))))))))) WITH CHECK ((is_developer() OR (has_site_permission('create_scales'::text) AND (NOT (EXISTS ( SELECT 1
   FROM assignments a
  WHERE ((a.mass_id = masses.id) AND (NOT can_manage_service_group(a.service_group)))))))));
ALTER POLICY "messages_insert" ON public."messages" WITH CHECK ((has_site_permission('send_suggestions'::text) AND (user_id = auth.uid())));
ALTER POLICY "messages_read" ON public."messages" USING ((is_coordinator() OR (user_id = auth.uid())));
ALTER POLICY "notes_insert" ON public."notifications" WITH CHECK (has_site_permission('send_notifications'::text));
ALTER POLICY "notes_read" ON public."notifications" USING ((((user_id = auth.uid()) AND has_site_permission('read_notifications'::text)) OR has_site_permission('send_notifications'::text)));
ALTER POLICY "notes_update" ON public."notifications" USING ((user_id = auth.uid())) WITH CHECK ((user_id = auth.uid()));
ALTER POLICY "profile_read" ON public."profiles" USING (((id = auth.uid()) OR has_site_permission('manage_users'::text) OR is_coordinator() OR (is_approved() AND approved)));
ALTER POLICY "profile_self" ON public."profiles" USING (((id = auth.uid()) OR has_site_permission('manage_users'::text) OR is_coordinator())) WITH CHECK (((id = auth.uid()) OR has_site_permission('manage_users'::text) OR is_coordinator()));
ALTER POLICY "requests_insert" ON public."requests" WITH CHECK (((status = 'pendente'::text) AND (user_id = auth.uid()) AND is_approved() AND (EXISTS ( SELECT 1
   FROM profiles p
  WHERE ((p.id = auth.uid()) AND p.approved AND (p.role = requests.service_group) AND (p.role = ANY (ARRAY['coroinha'::text, 'cerimoniario'::text]))))) AND (EXISTS ( SELECT 1
   FROM masses m
  WHERE ((m.id = requests.mass_id) AND m.published AND (m.starts_at > now())))) AND (((type = 'servir'::text) AND (assignment_id IS NULL) AND (EXISTS ( SELECT 1
   FROM assignments a
  WHERE ((a.mass_id = requests.mass_id) AND (a.service_group = requests.service_group) AND ((a.server_id IS NULL) OR (a.status = 'desmarcado'::text)))))) OR ((type = 'substituir'::text) AND (assignment_id IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM assignments a
  WHERE ((a.id = requests.assignment_id) AND (a.mass_id = requests.mass_id) AND (a.service_group = requests.service_group) AND (a.status = 'desmarcado'::text) AND (a.server_id IS DISTINCT FROM auth.uid())))))) AND (NOT (EXISTS ( SELECT 1
   FROM assignments a
  WHERE ((a.mass_id = requests.mass_id) AND (a.server_id = auth.uid()) AND (a.status <> 'desmarcado'::text)))))));
ALTER POLICY "requests_manage" ON public."requests" USING ((has_site_permission('approve_requests'::text) AND can_manage_service_group(service_group))) WITH CHECK ((has_site_permission('approve_requests'::text) AND can_manage_service_group(service_group)));
ALTER POLICY "requests_read" ON public."requests" USING ((can_manage_service_group(service_group) OR (user_id = auth.uid())));
ALTER POLICY "screen_announcement_insert" ON public."screen_announcements" WITH CHECK ((has_site_permission('send_popup'::text) AND (created_by = auth.uid())));
ALTER POLICY "screen_announcement_read" ON public."screen_announcements" USING ((has_site_permission('send_popup'::text) OR (EXISTS ( SELECT 1
   FROM profiles me
  WHERE ((me.id = auth.uid()) AND me.approved AND screen_announcements.active AND ((screen_announcements.target_role = 'all'::text) OR ((screen_announcements.target_role = 'individual'::text) AND (screen_announcements.target_user_id = me.id)) OR (screen_announcements.target_role = me.role)))))));
ALTER POLICY "screen_announcement_update" ON public."screen_announcements" USING (has_site_permission('send_popup'::text)) WITH CHECK (has_site_permission('send_popup'::text));
ALTER POLICY "site_updates_add" ON public."site_updates" WITH CHECK (has_site_permission('publish_updates'::text));
ALTER POLICY "site_updates_delete" ON public."site_updates" USING (has_site_permission('publish_updates'::text));
ALTER POLICY "site_updates_edit" ON public."site_updates" USING (has_site_permission('publish_updates'::text)) WITH CHECK (has_site_permission('publish_updates'::text));
ALTER POLICY "site_updates_read" ON public."site_updates" USING (is_approved());
DROP TRIGGER IF EXISTS service_settings_audit ON public.service_settings;
CREATE TRIGGER service_settings_audit AFTER INSERT OR UPDATE OR DELETE ON public.service_settings FOR EACH ROW EXECUTE FUNCTION public.audit_record_change();
DROP TRIGGER IF EXISTS permission_rules_audit ON public.permission_rules;
CREATE TRIGGER permission_rules_audit AFTER INSERT OR UPDATE OR DELETE ON public.permission_rules FOR EACH ROW EXECUTE FUNCTION public.audit_record_change();
REVOKE ALL ON public.permission_catalog,public.automation_catalog FROM PUBLIC,coroinhas_app,coroinhas_gateway;
REVOKE ALL ON FUNCTION public.developer_permission_snapshot(uuid),public.developer_apply_permissions(uuid,jsonb,timestamptz,text),public.developer_revoke_permission(uuid,text),public.developer_automation_snapshot(),public.developer_apply_automations(jsonb,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.developer_permission_snapshot(uuid),public.developer_apply_permissions(uuid,jsonb,timestamptz,text),public.developer_revoke_permission(uuid,text),public.developer_automation_snapshot(),public.developer_apply_automations(jsonb,text),public.my_site_permissions(),public.automation_enabled(text) TO coroinhas_app,coroinhas_gateway;

-- Complemento: verificação obrigatória de pedidos e de presença no servidor.
ALTER POLICY requests_insert ON public.requests WITH CHECK ((has_site_permission('request_service'::text) AND ((status = 'pendente'::text) AND (user_id = auth.uid()) AND is_approved() AND (EXISTS ( SELECT 1
   FROM profiles p
  WHERE ((p.id = auth.uid()) AND p.approved AND (p.role = requests.service_group) AND (p.role = ANY (ARRAY['coroinha'::text, 'cerimoniario'::text]))))) AND (EXISTS ( SELECT 1
   FROM masses m
  WHERE ((m.id = requests.mass_id) AND m.published AND (m.starts_at > now())))) AND (((type = 'servir'::text) AND (assignment_id IS NULL) AND (EXISTS ( SELECT 1
   FROM assignments a
  WHERE ((a.mass_id = requests.mass_id) AND (a.service_group = requests.service_group) AND ((a.server_id IS NULL) OR (a.status = 'desmarcado'::text)))))) OR ((type = 'substituir'::text) AND (assignment_id IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM assignments a
  WHERE ((a.id = requests.assignment_id) AND (a.mass_id = requests.mass_id) AND (a.service_group = requests.service_group) AND (a.status = 'desmarcado'::text) AND (a.server_id IS DISTINCT FROM auth.uid())))))) AND (NOT (EXISTS ( SELECT 1
   FROM assignments a
  WHERE ((a.mass_id = requests.mass_id) AND (a.server_id = auth.uid()) AND (a.status <> 'desmarcado'::text))))))));
CREATE OR REPLACE FUNCTION public.guard_assignment_attendance_permission()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$ BEGIN IF NEW.status IS DISTINCT FROM OLD.status AND NEW.status IN ('presente','faltou') AND NOT public.has_site_permission('attendance') THEN RAISE EXCEPTION 'Sem permissão para registrar presença ou falta' USING ERRCODE='42501'; END IF; RETURN NEW; END $function$;
DROP TRIGGER IF EXISTS guard_assignment_attendance_permission_trg ON public.assignments;
CREATE TRIGGER guard_assignment_attendance_permission_trg BEFORE UPDATE ON public.assignments FOR EACH ROW EXECUTE FUNCTION public.guard_assignment_attendance_permission();
