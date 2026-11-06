-- ONLY the isolated migration branch. Never execute against Supabase or production.
-- Reviewed source snapshot: 2026-11-06. Apply once, atomically.
CREATE ROLE coroinhas_app NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS;
GRANT coroinhas_app TO coroinhas_owner;
CREATE SCHEMA migration_private;
REVOKE ALL ON SCHEMA migration_private FROM PUBLIC;
CREATE TABLE migration_private.environment (id boolean PRIMARY KEY DEFAULT true CHECK(id), branch_id text NOT NULL);
INSERT INTO migration_private.environment VALUES(true,'br-rough-hill-bcj6lzt1');
CREATE SCHEMA auth;
REVOKE ALL ON SCHEMA auth FROM PUBLIC;
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$ SELECT nullif(current_setting('app.user_id',true),'')::uuid $$;
REVOKE ALL ON FUNCTION auth.uid() FROM PUBLIC;
GRANT USAGE ON SCHEMA public,auth TO coroinhas_app;
GRANT EXECUTE ON FUNCTION auth.uid() TO coroinhas_app;
CREATE TABLE migration_private.identity_map(provider text NOT NULL,subject text NOT NULL,profile_id uuid NOT NULL REFERENCES public.profiles(id),PRIMARY KEY(provider,subject),UNIQUE(provider,profile_id));
INSERT INTO migration_private.identity_map SELECT 'supabase',id::text,id FROM public.profiles;
CREATE TABLE migration_private.push_outbox(notification_id uuid PRIMARY KEY REFERENCES public.notifications(id) ON DELETE CASCADE,created_at timestamptz NOT NULL DEFAULT now(),state text NOT NULL DEFAULT 'suppressed' CHECK(state IN ('suppressed','pending','sent','failed')));
CREATE FUNCTION migration_private.queue_push_notice() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$ BEGIN INSERT INTO migration_private.push_outbox(notification_id) VALUES(NEW.id) ON CONFLICT DO NOTHING; RETURN NEW; END $$;
REVOKE ALL ON FUNCTION migration_private.queue_push_notice() FROM PUBLIC;
CREATE TRIGGER queue_push AFTER INSERT ON public.notifications FOR EACH ROW EXECUTE FUNCTION migration_private.queue_push_notice();

CREATE OR REPLACE FUNCTION public.approve_service_request(p_request_id uuid, p_assignment_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_request public.requests%rowtype;
 v_assignment public.assignments%rowtype;
begin
 if auth.uid() is null or not public.is_coordinator() then
   raise exception 'Somente a coordenação pode aprovar solicitações.' using errcode='42501';
 end if;
 if p_request_id is null or p_assignment_id is null then
   raise exception 'Selecione uma solicitação e uma função.';
 end if;
 select * into v_request from public.requests where id=p_request_id for update;
 if not found or v_request.status <> 'pendente' then
   raise exception 'Este pedido não está mais pendente.';
 end if;
 select * into v_assignment from public.assignments where id=p_assignment_id for update;
 if not found or v_assignment.mass_id<>v_request.mass_id then
   raise exception 'A função não pertence à missa solicitada.';
 end if;
 if v_request.type='substituir' and v_request.assignment_id is distinct from p_assignment_id then
   raise exception 'Para substituição, escolha a função indicada na solicitação.';
 end if;
 if v_request.type <> 'substituir' and v_assignment.server_id is not null and v_assignment.status<>'desmarcado' then
   raise exception 'Esta função já está ocupada. Atualize a lista de vagas.';
 end if;
 if exists(select 1 from public.assignments a where a.mass_id=v_request.mass_id and a.server_id=v_request.user_id and a.status<>'desmarcado' and a.id<>p_assignment_id) then
   raise exception 'Este coroinha já possui uma função nesta missa.';
 end if;
 update public.assignments
 set server_id=v_request.user_id,status='escalado',reason=null
 where id=v_assignment.id;
 update public.requests set status='aprovado' where id=v_request.id;
end;
$function$
;

REVOKE ALL ON FUNCTION public.approve_service_request(p_request_id uuid, p_assignment_id uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.approve_service_request(p_request_id uuid, p_assignment_id uuid) TO coroinhas_app;

CREATE OR REPLACE FUNCTION public.audit_record_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_actor uuid := auth.uid(); v_before jsonb; v_after jsonb; v_id text; v_email text;
BEGIN
 IF TG_OP IN ('UPDATE','DELETE') THEN v_before:=to_jsonb(OLD);END IF;
 IF TG_OP IN ('INSERT','UPDATE') THEN v_after:=to_jsonb(NEW);END IF;
 IF TG_TABLE_NAME='profiles' THEN
  v_before:=v_before - 'notification_preferences' - 'last_seen_at';
  v_after:=v_after - 'notification_preferences' - 'last_seen_at';
 END IF;
 IF TG_OP='UPDATE' AND v_before IS NOT DISTINCT FROM v_after THEN RETURN NEW; END IF;
 v_id:=coalesce(v_after->>'id',v_before->>'id',v_after->>'user_id',v_before->>'user_id');
 SELECT email INTO v_email FROM public.profiles WHERE id=v_actor;
 INSERT INTO public.audit_log(actor_id,actor_email,table_name,action,record_id,before_data,after_data)
 VALUES(v_actor,v_email,TG_TABLE_NAME,TG_OP,v_id,v_before,v_after);
 RETURN CASE WHEN TG_OP='DELETE' THEN OLD ELSE NEW END;
END $function$
;

REVOKE ALL ON FUNCTION public.audit_record_change() FROM PUBLIC;

CREATE OR REPLACE FUNCTION public.delete_notification(p_group uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
 IF NOT public.is_coordinator() THEN RAISE EXCEPTION 'Acesso negado'; END IF;
 DELETE FROM public.notifications WHERE group_id=p_group;
END $function$
;

REVOKE ALL ON FUNCTION public.delete_notification(p_group uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.delete_notification(p_group uuid) TO coroinhas_app;

CREATE OR REPLACE FUNCTION public.developer_usage_summary()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
 IF NOT public.is_developer() THEN RAISE EXCEPTION 'Sem acesso'; END IF;
 RETURN jsonb_build_object('total_users',(SELECT count(*) FROM public.profiles),'approved_users',(SELECT count(*) FROM public.profiles WHERE approved),'pending_users',(SELECT count(*) FROM public.profiles WHERE NOT approved),'servers',(SELECT count(*) FROM public.profiles WHERE role='coroinha' AND approved),'parents',(SELECT count(*) FROM public.profiles WHERE role='pai' AND approved),'coordinators',(SELECT count(*) FROM public.profiles WHERE role='coordenadora' AND approved),'developers',(SELECT count(*) FROM public.profiles WHERE role='desenvolvedor' AND approved),'active_15m',(SELECT count(*) FROM public.profiles WHERE last_seen_at>now()-interval '15 minutes'),'logins_recorded',(SELECT count(*) FROM public.login_events),'db_size_bytes',pg_database_size(current_database()),'masses',(SELECT count(*) FROM public.masses),'notifications',(SELECT count(*) FROM public.notifications));
END $function$
;

REVOKE ALL ON FUNCTION public.developer_usage_summary() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.developer_usage_summary() TO coroinhas_app;

CREATE OR REPLACE FUNCTION public.edit_notification(p_group uuid, p_title text, p_body text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
 IF NOT public.is_coordinator() THEN RAISE EXCEPTION 'Acesso negado'; END IF;
 IF length(trim(coalesce(p_title,'')))=0 OR length(trim(coalesce(p_body,'')))=0 THEN RAISE EXCEPTION 'Preencha titulo e mensagem'; END IF;
 UPDATE public.notifications SET title=trim(p_title),body=trim(p_body),seen=false,read_at=NULL,created_at=now() WHERE group_id=p_group;
 IF NOT FOUND THEN RAISE EXCEPTION 'Aviso nao encontrado'; END IF;
END $function$
;

REVOKE ALL ON FUNCTION public.edit_notification(p_group uuid, p_title text, p_body text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.edit_notification(p_group uuid, p_title text, p_body text) TO coroinhas_app;

CREATE OR REPLACE FUNCTION public.is_approved()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
 select exists(
  select 1 from public.profiles
  where id=auth.uid() and approved=true
 );
$function$
;

REVOKE ALL ON FUNCTION public.is_approved() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.is_approved() TO coroinhas_app;

CREATE OR REPLACE FUNCTION public.is_coordinator()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ SELECT EXISTS(SELECT 1 FROM public.profiles WHERE id=auth.uid() AND approved AND role IN ('coordenadora','desenvolvedor')) $function$
;

REVOKE ALL ON FUNCTION public.is_coordinator() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.is_coordinator() TO coroinhas_app;

CREATE OR REPLACE FUNCTION public.is_developer()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ SELECT EXISTS(SELECT 1 FROM public.profiles WHERE id=auth.uid() AND approved AND role='desenvolvedor') $function$
;

REVOKE ALL ON FUNCTION public.is_developer() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.is_developer() TO coroinhas_app;

CREATE OR REPLACE FUNCTION public.mark_coordinator_message_seen(p_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
 IF NOT public.is_coordinator() THEN RAISE EXCEPTION 'Acesso restrito'; END IF;
 UPDATE public.messages SET seen=true,read_at=now() WHERE id=p_id AND seen=false;
END $function$
;

REVOKE ALL ON FUNCTION public.mark_coordinator_message_seen(p_id uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.mark_coordinator_message_seen(p_id uuid) TO coroinhas_app;

CREATE OR REPLACE FUNCTION public.mark_notification_seen(p_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Acesso negado'; END IF;
 UPDATE public.notifications SET seen=true,read_at=now() WHERE id=p_id AND user_id=auth.uid() AND seen=false;
END $function$
;

REVOKE ALL ON FUNCTION public.mark_notification_seen(p_id uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.mark_notification_seen(p_id uuid) TO coroinhas_app;

CREATE OR REPLACE FUNCTION public.notify_coordinator_message()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin

 insert into public.notifications(
  user_id,title,body
 )
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
  ' enviou uma mensagem. Abra Reclamações e Sugestões.'

 from public.profiles p
 where p.approved
 and p.role='coordenadora';

 return new;

end;
$function$
;

REVOKE ALL ON FUNCTION public.notify_coordinator_message() FROM PUBLIC;

CREATE OR REPLACE FUNCTION public.notify_coordinator_request()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare server_name text; mass_label text;
begin
 select coalesce(nullif(trim(name),''),'Coroinha') into server_name from public.profiles where id=new.user_id;
 select coalesce(title,'missa') || ' de ' || to_char(starts_at at time zone 'America/Sao_Paulo','DD/MM/YYYY "às" HH24:MI')
 into mass_label from public.masses where id=new.mass_id;
 insert into public.notifications(user_id,title,body)
 select p.id,
 case when new.type='substituir' then 'Solicitação de substituição' else 'Pedido para servir' end,
 coalesce(server_name,'Coroinha') || case when new.type='substituir' then ' solicitou substituição na ' else ' quer servir na ' end || coalesce(mass_label,'missa selecionada') || '.'
 from public.profiles p where p.approved=true and p.role='coordenadora';
 return new;
end $function$
;

REVOKE ALL ON FUNCTION public.notify_coordinator_request() FROM PUBLIC;

CREATE OR REPLACE FUNCTION public.notify_pending_approval()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
 if new.approved is false then
  insert into public.notifications(user_id,title,body)
  select p.id,'Cadastro aguardando aprovação',
  coalesce(nullif(trim(new.name),''),'Novo usuário') || ' está aguardando aprovação de cadastro.'
  from public.profiles p where p.approved=true and p.role='coordenadora' and p.id<>new.id;
 end if;
 return new;
end $function$
;

REVOKE ALL ON FUNCTION public.notify_pending_approval() FROM PUBLIC;

CREATE OR REPLACE FUNCTION public.reassign_legacy_function(p_old_assignment_id uuid, p_open_assignment_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_old public.assignments%rowtype; v_open public.assignments%rowtype;
begin
 if auth.uid() is null or not public.is_coordinator() then raise exception 'Acesso restrito à coordenação.' using errcode='42501'; end if;
 if p_old_assignment_id is null or p_open_assignment_id is null or p_old_assignment_id=p_open_assignment_id then raise exception 'Selecione uma vaga diferente.'; end if;
 perform 1 from public.assignments where id in (p_old_assignment_id,p_open_assignment_id) order by id for update;
 select * into v_old from public.assignments where id=p_old_assignment_id;
 select * into v_open from public.assignments where id=p_open_assignment_id;
 if v_old.id is null or v_open.id is null or v_old.mass_id<>v_open.mass_id
 then raise exception 'As funções devem pertencer à mesma missa.'; end if;
 if v_old.function_name<>'A definir' or v_old.server_id is null or v_old.status='desmarcado'
 then raise exception 'A escala antiga não pode ser convertida.'; end if;
 if v_open.server_id is not null and v_open.status<>'desmarcado'
 then raise exception 'A vaga selecionada já está ocupada.'; end if;
 update public.assignments
 set server_id=v_old.server_id, status=v_old.status, reason=v_old.reason
 where id=v_open.id;
 delete from public.assignments where id=v_old.id;
end; $function$
;

REVOKE ALL ON FUNCTION public.reassign_legacy_function(p_old_assignment_id uuid, p_open_assignment_id uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.reassign_legacy_function(p_old_assignment_id uuid, p_open_assignment_id uuid) TO coroinhas_app;

CREATE OR REPLACE FUNCTION public.record_site_access(p_login boolean DEFAULT false)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Nao autenticado'; END IF;
 UPDATE public.profiles SET last_seen_at=now() WHERE id=auth.uid();
 IF p_login THEN INSERT INTO public.login_events(user_id) VALUES(auth.uid()); END IF;
END $function$
;

REVOKE ALL ON FUNCTION public.record_site_access(p_login boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.record_site_access(p_login boolean) TO coroinhas_app;

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
  if t<=now() then raise exception 'A missa já começou'; end if;
  if length(trim(coalesce(p_reason,'')))<3 then
   raise exception 'Informe uma justificativa com pelo menos 3 caracteres';
  end if;
  if v.status in ('desmarcado','faltou','presente') then
   raise exception 'Esta escala não permite desistência';
  end if;
  update public.assignments set status='desmarcado',reason=trim(p_reason) where id=p_id;
  insert into public.notifications(user_id,title,body)
  select id,'Vaga para substituição','Função: '||v.function_name||' • '||
     to_char(t at time zone 'America/Sao_Paulo','DD/MM/YYYY HH24:MI')
  from public.profiles where approved=true and id<>auth.uid();
 elsif p_action='confirmar' then
  if t<=now() then raise exception 'Não é possível confirmar uma missa que já começou'; end if;
  if v.status not in ('escalado','confirmado') then
   raise exception 'Esta escala não pode ser confirmada';
  end if;
  update public.assignments set status='confirmado' where id=p_id;
 else
  raise exception 'Ação inválida';
 end if;
end;
$function$
;

REVOKE ALL ON FUNCTION public.respond_assignment(p_id uuid, p_action text, p_reason text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.respond_assignment(p_id uuid, p_action text, p_reason text) TO coroinhas_app;

CREATE OR REPLACE FUNCTION public.send_notification(p_title text, p_body text, p_recipient uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_group uuid:=gen_random_uuid();
BEGIN
 IF NOT public.is_coordinator() THEN RAISE EXCEPTION 'Acesso negado'; END IF;
 IF length(trim(coalesce(p_title,'')))=0 OR length(trim(coalesce(p_body,'')))=0 THEN RAISE EXCEPTION 'Preencha titulo e mensagem'; END IF;
 INSERT INTO public.notifications(user_id,title,body,group_id,seen,read_at)
 SELECT p.id,trim(p_title),trim(p_body),v_group,false,NULL FROM public.profiles p
 WHERE p.approved=true AND p.role='coroinha' AND (p_recipient IS NULL OR p.id=p_recipient);
 IF NOT FOUND THEN RAISE EXCEPTION 'Nenhum destinatario encontrado'; END IF;
 RETURN v_group;
END $function$
;

REVOKE ALL ON FUNCTION public.send_notification(p_title text, p_body text, p_recipient uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.send_notification(p_title text, p_body text, p_recipient uuid) TO coroinhas_app;

CREATE OR REPLACE FUNCTION public.validate_notification_preferences()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
 IF NEW.notification_preferences IS DISTINCT FROM OLD.notification_preferences AND
   (jsonb_typeof(NEW.notification_preferences) <> 'object' OR
    EXISTS (SELECT 1 FROM jsonb_each(NEW.notification_preferences) v WHERE jsonb_typeof(v.value) <> 'boolean') OR
    NEW.notification_preferences ?| ARRAY['enabled','free_slots','withdrawals','new_schedules'] = false) THEN
   RAISE EXCEPTION 'Preferencias de notificacao invalidas';
 END IF;
 RETURN NEW;
END $function$
;

REVOKE ALL ON FUNCTION public.validate_notification_preferences() FROM PUBLIC;

CREATE FUNCTION public.protect_profile() RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$
BEGIN
 IF NEW.id IS DISTINCT FROM OLD.id OR NEW.email IS DISTINCT FROM OLD.email THEN RAISE EXCEPTION 'Identidade imutável nesta fase' USING ERRCODE='42501'; END IF;
 IF NEW.role IS DISTINCT FROM OLD.role AND NOT public.is_developer() THEN RAISE EXCEPTION 'Somente desenvolvedor altera papéis' USING ERRCODE='42501'; END IF;
 IF (NEW.approved IS DISTINCT FROM OLD.approved OR NEW.notes IS DISTINCT FROM OLD.notes) AND NOT public.is_coordinator() THEN RAISE EXCEPTION 'Acesso restrito à coordenação' USING ERRCODE='42501'; END IF;
 IF NOT public.is_developer() AND OLD.role IN ('coordenadora','desenvolvedor') AND NEW.approved IS DISTINCT FROM OLD.approved THEN RAISE EXCEPTION 'Somente desenvolvedor gerencia perfis especiais' USING ERRCODE='42501'; END IF;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.protect_profile() FROM PUBLIC;
CREATE FUNCTION public.guard_notification_edit() RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$ BEGIN
 IF current_user='coroinhas_app' THEN RAISE EXCEPTION 'Use as funções autorizadas' USING ERRCODE='42501'; END IF; RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.guard_notification_edit() FROM PUBLIC;

CREATE POLICY "assignment_manage" ON public."assignments" AS PERMISSIVE FOR ALL TO coroinhas_app USING (is_coordinator()) WITH CHECK (is_coordinator());

CREATE POLICY "assignment_read" ON public."assignments" AS PERMISSIVE FOR SELECT TO coroinhas_app USING ((is_coordinator() OR (is_approved() AND (EXISTS ( SELECT 1
   FROM masses
  WHERE ((masses.id = assignments.mass_id) AND masses.published))))));

CREATE POLICY "audit_developer_read" ON public."audit_log" AS PERMISSIVE FOR SELECT TO coroinhas_app USING (is_developer());

CREATE POLICY "fixed_manage" ON public."fixed_rules" AS PERMISSIVE FOR ALL TO coroinhas_app USING (is_coordinator()) WITH CHECK (is_coordinator());

CREATE POLICY "fixed_read" ON public."fixed_rules" AS PERMISSIVE FOR SELECT TO coroinhas_app USING ((is_coordinator() OR (server_id = auth.uid())));

CREATE POLICY "guides_manage" ON public."guides" AS PERMISSIVE FOR ALL TO coroinhas_app USING (is_coordinator()) WITH CHECK (is_coordinator());

CREATE POLICY "guides_read" ON public."guides" AS PERMISSIVE FOR SELECT TO coroinhas_app USING (is_approved());

CREATE POLICY "mass_manage" ON public."masses" AS PERMISSIVE FOR ALL TO coroinhas_app USING (is_coordinator()) WITH CHECK (is_coordinator());

CREATE POLICY "mass_read" ON public."masses" AS PERMISSIVE FOR SELECT TO coroinhas_app USING ((is_coordinator() OR (is_approved() AND published)));

CREATE POLICY "messages_insert" ON public."messages" AS PERMISSIVE FOR INSERT TO coroinhas_app WITH CHECK ((is_approved() AND (user_id = auth.uid())));

CREATE POLICY "messages_read" ON public."messages" AS PERMISSIVE FOR SELECT TO coroinhas_app USING ((is_coordinator() OR (user_id = auth.uid())));

CREATE POLICY "notes_insert" ON public."notifications" AS PERMISSIVE FOR INSERT TO coroinhas_app WITH CHECK (is_coordinator());

CREATE POLICY "notes_read" ON public."notifications" AS PERMISSIVE FOR SELECT TO coroinhas_app USING (((user_id = auth.uid()) OR is_coordinator()));

CREATE POLICY "notes_update" ON public."notifications" AS PERMISSIVE FOR UPDATE TO coroinhas_app USING ((user_id = auth.uid())) WITH CHECK ((user_id = auth.uid()));

CREATE POLICY "profile_read" ON public."profiles" AS PERMISSIVE FOR SELECT TO coroinhas_app USING (((id = auth.uid()) OR is_coordinator() OR (is_approved() AND approved)));

CREATE POLICY "profile_self" ON public."profiles" AS PERMISSIVE FOR UPDATE TO coroinhas_app USING (((id = auth.uid()) OR is_coordinator())) WITH CHECK (((id = auth.uid()) OR is_coordinator()));

CREATE POLICY "push_delete_own" ON public."push_subscriptions" AS PERMISSIVE FOR DELETE TO coroinhas_app USING ((user_id = auth.uid()));

CREATE POLICY "push_insert_own" ON public."push_subscriptions" AS PERMISSIVE FOR INSERT TO coroinhas_app WITH CHECK ((user_id = auth.uid()));

CREATE POLICY "push_select_own" ON public."push_subscriptions" AS PERMISSIVE FOR SELECT TO coroinhas_app USING ((user_id = auth.uid()));

CREATE POLICY "push_update_own" ON public."push_subscriptions" AS PERMISSIVE FOR UPDATE TO coroinhas_app USING ((user_id = auth.uid())) WITH CHECK ((user_id = auth.uid()));

CREATE POLICY "requests_insert" ON public."requests" AS PERMISSIVE FOR INSERT TO coroinhas_app WITH CHECK ((is_approved() AND (user_id = auth.uid()) AND (status = 'pendente'::text)));

CREATE POLICY "requests_manage" ON public."requests" AS PERMISSIVE FOR UPDATE TO coroinhas_app USING (is_coordinator()) WITH CHECK (is_coordinator());

CREATE POLICY "requests_read" ON public."requests" AS PERMISSIVE FOR SELECT TO coroinhas_app USING ((is_coordinator() OR (user_id = auth.uid())));

CREATE POLICY "screen_dismissals_insert" ON public."screen_announcement_dismissals" AS PERMISSIVE FOR INSERT TO coroinhas_app WITH CHECK (((user_id = ( SELECT auth.uid() AS uid)) AND (EXISTS ( SELECT 1
   FROM screen_announcements a
  WHERE ((a.id = screen_announcement_dismissals.announcement_id) AND a.active)))));

CREATE POLICY "screen_dismissals_read" ON public."screen_announcement_dismissals" AS PERMISSIVE FOR SELECT TO coroinhas_app USING ((user_id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "screen_dismissals_update" ON public."screen_announcement_dismissals" AS PERMISSIVE FOR UPDATE TO coroinhas_app USING ((user_id = ( SELECT auth.uid() AS uid))) WITH CHECK (((user_id = ( SELECT auth.uid() AS uid)) AND (EXISTS ( SELECT 1
   FROM screen_announcements a
  WHERE ((a.id = screen_announcement_dismissals.announcement_id) AND a.active)))));

CREATE POLICY "screen_announcement_insert" ON public."screen_announcements" AS PERMISSIVE FOR INSERT TO coroinhas_app WITH CHECK (((created_by = ( SELECT auth.uid() AS uid)) AND (EXISTS ( SELECT 1
   FROM profiles me
  WHERE ((me.id = ( SELECT auth.uid() AS uid)) AND (me.role = 'desenvolvedor'::text) AND me.approved)))));

CREATE POLICY "screen_announcement_read" ON public."screen_announcements" AS PERMISSIVE FOR SELECT TO coroinhas_app USING ((EXISTS ( SELECT 1
   FROM profiles me
  WHERE ((me.id = ( SELECT auth.uid() AS uid)) AND me.approved AND ((me.role = 'desenvolvedor'::text) OR (screen_announcements.active AND ((screen_announcements.target_role = 'all'::text) OR ((screen_announcements.target_role = 'individual'::text) AND (screen_announcements.target_user_id = me.id)) OR (screen_announcements.target_role = me.role))))))));

CREATE POLICY "screen_announcement_update" ON public."screen_announcements" AS PERMISSIVE FOR UPDATE TO coroinhas_app USING ((EXISTS ( SELECT 1
   FROM profiles me
  WHERE ((me.id = ( SELECT auth.uid() AS uid)) AND (me.role = 'desenvolvedor'::text) AND me.approved)))) WITH CHECK ((EXISTS ( SELECT 1
   FROM profiles me
  WHERE ((me.id = ( SELECT auth.uid() AS uid)) AND (me.role = 'desenvolvedor'::text) AND me.approved))));

CREATE POLICY "site_updates_add" ON public."site_updates" AS PERMISSIVE FOR INSERT TO coroinhas_app WITH CHECK (is_developer());

CREATE POLICY "site_updates_delete" ON public."site_updates" AS PERMISSIVE FOR DELETE TO coroinhas_app USING (is_developer());

CREATE POLICY "site_updates_edit" ON public."site_updates" AS PERMISSIVE FOR UPDATE TO coroinhas_app USING (is_developer()) WITH CHECK (is_developer());

CREATE POLICY "site_updates_read" ON public."site_updates" AS PERMISSIVE FOR SELECT TO coroinhas_app USING (is_approved());

GRANT INSERT ON public."profiles" TO coroinhas_app;

GRANT SELECT ON public."profiles" TO coroinhas_app;

GRANT UPDATE ON public."profiles" TO coroinhas_app;

GRANT DELETE ON public."profiles" TO coroinhas_app;

GRANT INSERT ON public."notifications" TO coroinhas_app;

GRANT SELECT ON public."notifications" TO coroinhas_app;

GRANT DELETE ON public."notifications" TO coroinhas_app;

GRANT INSERT ON public."masses" TO coroinhas_app;

GRANT SELECT ON public."masses" TO coroinhas_app;

GRANT UPDATE ON public."masses" TO coroinhas_app;

GRANT DELETE ON public."masses" TO coroinhas_app;

GRANT INSERT ON public."assignments" TO coroinhas_app;

GRANT SELECT ON public."assignments" TO coroinhas_app;

GRANT UPDATE ON public."assignments" TO coroinhas_app;

GRANT DELETE ON public."assignments" TO coroinhas_app;

GRANT INSERT ON public."requests" TO coroinhas_app;

GRANT SELECT ON public."requests" TO coroinhas_app;

GRANT UPDATE ON public."requests" TO coroinhas_app;

GRANT DELETE ON public."requests" TO coroinhas_app;

GRANT INSERT ON public."fixed_rules" TO coroinhas_app;

GRANT SELECT ON public."fixed_rules" TO coroinhas_app;

GRANT UPDATE ON public."fixed_rules" TO coroinhas_app;

GRANT DELETE ON public."fixed_rules" TO coroinhas_app;

GRANT INSERT ON public."messages" TO coroinhas_app;

GRANT SELECT ON public."messages" TO coroinhas_app;

GRANT UPDATE ON public."messages" TO coroinhas_app;

GRANT DELETE ON public."messages" TO coroinhas_app;

GRANT SELECT ON public."audit_log" TO coroinhas_app;

GRANT INSERT ON public."guides" TO coroinhas_app;

GRANT SELECT ON public."guides" TO coroinhas_app;

GRANT UPDATE ON public."guides" TO coroinhas_app;

GRANT DELETE ON public."guides" TO coroinhas_app;

GRANT INSERT ON public."site_updates" TO coroinhas_app;

GRANT SELECT ON public."site_updates" TO coroinhas_app;

GRANT UPDATE ON public."site_updates" TO coroinhas_app;

GRANT DELETE ON public."site_updates" TO coroinhas_app;

GRANT INSERT ON public."push_subscriptions" TO coroinhas_app;

GRANT SELECT ON public."push_subscriptions" TO coroinhas_app;

GRANT UPDATE ON public."push_subscriptions" TO coroinhas_app;

GRANT DELETE ON public."push_subscriptions" TO coroinhas_app;

GRANT INSERT ON public."screen_announcements" TO coroinhas_app;

GRANT SELECT ON public."screen_announcements" TO coroinhas_app;

GRANT UPDATE ON public."screen_announcements" TO coroinhas_app;

GRANT INSERT ON public."screen_announcement_dismissals" TO coroinhas_app;

GRANT SELECT ON public."screen_announcement_dismissals" TO coroinhas_app;

GRANT UPDATE ON public."screen_announcement_dismissals" TO coroinhas_app;

GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO coroinhas_app;

CREATE TRIGGER audit_change AFTER INSERT OR DELETE OR UPDATE ON public.assignments FOR EACH ROW EXECUTE FUNCTION audit_record_change();

CREATE TRIGGER audit_change AFTER INSERT OR DELETE OR UPDATE ON public.banned_emails FOR EACH ROW EXECUTE FUNCTION audit_record_change();

CREATE TRIGGER audit_change AFTER INSERT OR DELETE OR UPDATE ON public.fixed_rules FOR EACH ROW EXECUTE FUNCTION audit_record_change();

CREATE TRIGGER audit_change AFTER INSERT OR DELETE OR UPDATE ON public.guides FOR EACH ROW EXECUTE FUNCTION audit_record_change();

CREATE TRIGGER audit_change AFTER INSERT OR DELETE OR UPDATE ON public.masses FOR EACH ROW EXECUTE FUNCTION audit_record_change();

CREATE TRIGGER audit_change AFTER INSERT OR DELETE OR UPDATE ON public.messages FOR EACH ROW EXECUTE FUNCTION audit_record_change();

CREATE TRIGGER coroinhas_message_notify AFTER INSERT ON public.messages FOR EACH ROW EXECUTE FUNCTION notify_coordinator_message();

CREATE TRIGGER audit_change AFTER INSERT OR DELETE OR UPDATE ON public.notifications FOR EACH ROW EXECUTE FUNCTION audit_record_change();

CREATE TRIGGER guard_notification_edit_trigger BEFORE UPDATE ON public.notifications FOR EACH ROW EXECUTE FUNCTION guard_notification_edit();

CREATE TRIGGER audit_change AFTER INSERT OR DELETE OR UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION audit_record_change();

CREATE TRIGGER guard_profile BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION protect_profile();

CREATE TRIGGER notify_pending_profile_approval AFTER INSERT ON public.profiles FOR EACH ROW EXECUTE FUNCTION notify_pending_approval();

CREATE TRIGGER validate_notification_preferences_trigger BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION validate_notification_preferences();

CREATE TRIGGER audit_change AFTER INSERT OR DELETE OR UPDATE ON public.requests FOR EACH ROW EXECUTE FUNCTION audit_record_change();

CREATE TRIGGER coroinhas_request_notify AFTER INSERT ON public.requests FOR EACH ROW EXECUTE FUNCTION notify_coordinator_request();

CREATE TRIGGER audit_change AFTER INSERT OR DELETE OR UPDATE ON public.site_updates FOR EACH ROW EXECUTE FUNCTION audit_record_change();

SELECT setval(pg_get_serial_sequence('public.audit_log','id'),greatest(coalesce((select max(id) from public.audit_log),0)+1,1),false),setval(pg_get_serial_sequence('public.login_events','id'),greatest(coalesce((select max(id) from public.login_events),0)+1,1),false);

-- No auth.users mutations, no live HTTP webhook, no credentials copied.
-- Auth lifecycle management stays disabled until the identity migration is validated.
