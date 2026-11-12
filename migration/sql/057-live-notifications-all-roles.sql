-- Production notification compatibility for Neon Auth.
CREATE OR REPLACE FUNCTION public.notify_approved_profile() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $fn$
DECLARE v_key text; v_subject text;
BEGIN
 IF NOT public.automation_enabled('notify_profile_approved') THEN RETURN NEW; END IF;
 IF OLD.approved IS FALSE AND NEW.approved IS TRUE THEN
  v_key:=CASE NEW.role WHEN 'coroinha' THEN 'server_approval' WHEN 'cerimoniario' THEN 'ceremony_approval' WHEN 'desenvolvedor' THEN 'developer_system' ELSE 'general' END;
  v_subject:=CASE NEW.role WHEN 'coroinha' THEN 'Coroinhas' WHEN 'cerimoniario' THEN 'Cerimoniários' WHEN 'pai' THEN 'Responsáveis' WHEN 'coordenadora' THEN 'Coordenação' ELSE 'Desenvolvedor' END;
  INSERT INTO public.notifications(user_id,title,body,event_key) VALUES(NEW.id,'Cadastro aprovado','Seu acesso ao '||v_subject||' foi aprovado. Bem-vindo(a)!',v_key);
 END IF;
 RETURN NEW;
END $fn$;

CREATE OR REPLACE FUNCTION public.notify_pending_approval() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $fn$
DECLARE v_group text;
BEGIN
 IF NOT public.automation_enabled('notify_profile_pending') OR NEW.approved IS DISTINCT FROM FALSE THEN RETURN NEW; END IF;
 v_group:=CASE WHEN NEW.role='cerimoniario' OR (NEW.role='coordenadora' AND NEW.coordination_group='cerimoniario') THEN 'cerimoniario' ELSE 'coroinha' END;
 INSERT INTO public.notifications(user_id,title,body,event_key)
 SELECT p.id,'Cadastro aguardando aprovação',coalesce(nullif(trim(NEW.name),''),'Novo usuário')||' está aguardando aprovação ('||NEW.role||').',
 CASE WHEN p.role='desenvolvedor' THEN 'developer_system' ELSE 'coord_new_accounts' END
 FROM public.profiles p WHERE p.approved AND p.id<>NEW.id
 AND (p.role='desenvolvedor' OR (p.role='coordenadora' AND p.coordination_group=v_group));
 RETURN NEW;
END $fn$;

CREATE OR REPLACE FUNCTION public.notify_assignment_events() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $fn$
DECLARE v_mass public.masses%rowtype; v_name text; v_group text;
BEGIN
 IF NOT public.automation_enabled('notify_assignment_events') THEN RETURN NEW; END IF;
 SELECT * INTO v_mass FROM public.masses WHERE id=NEW.mass_id;
 IF NOT FOUND OR NOT v_mass.published THEN RETURN NEW; END IF;
 v_group:=NEW.service_group;
 SELECT coalesce(nullif(trim(name),''),'Integrante') INTO v_name FROM public.profiles WHERE id=NEW.server_id;
 IF NEW.server_id IS NOT NULL AND NEW.status NOT IN ('desmarcado','faltou')
   AND (TG_OP='INSERT' OR OLD.server_id IS DISTINCT FROM NEW.server_id OR (OLD.status='desmarcado' AND NEW.status='escalado')) THEN
  INSERT INTO public.notifications(user_id,title,body,event_key)
  SELECT p.id,'Você foi escalado(a)',
   'Você está na escala de '||v_mass.title||' em '||to_char(v_mass.starts_at AT TIME ZONE 'America/Sao_Paulo','DD/MM/YYYY "às" HH24:MI')||'.',
   CASE WHEN v_group='cerimoniario' THEN 'ceremony_assignments' ELSE 'server_assignments' END
  FROM public.profiles p WHERE p.id=NEW.server_id AND p.approved AND p.role=v_group;
  IF v_group='coroinha' THEN
   INSERT INTO public.notifications(user_id,title,body,event_key)
   SELECT l.parent_id,'Seu filho foi escalado',
   coalesce(v_name,'O coroinha')||' entrou na escala de '||v_mass.title||'.','parent_assignments'
   FROM public.parent_child_links l JOIN public.profiles p ON p.id=l.parent_id AND p.approved AND p.role='pai'
   WHERE l.child_id=NEW.server_id;
  END IF;
 END IF;
 IF TG_OP='UPDATE' AND OLD.status IS DISTINCT FROM NEW.status
 AND NEW.status IN ('confirmado','desmarcado') AND NEW.server_id IS NOT NULL THEN
  INSERT INTO public.notifications(user_id,title,body,event_key)
  SELECT p.id,CASE WHEN NEW.status='confirmado' THEN 'Escala confirmada' ELSE 'Escala desmarcada' END,
   coalesce(v_name,'Integrante')||CASE WHEN NEW.status='confirmado' THEN ' confirmou participação em ' ELSE ' desmarcou a escala de ' END||v_mass.title||'.',
   CASE WHEN p.role='desenvolvedor' THEN 'developer_system' ELSE 'coord_responses' END
  FROM public.profiles p WHERE p.approved AND
   (p.role='desenvolvedor' OR (p.role='coordenadora' AND p.coordination_group=v_group));
  IF v_group='coroinha' THEN
   INSERT INTO public.notifications(user_id,title,body,event_key)
   SELECT l.parent_id,CASE WHEN NEW.status='confirmado' THEN 'Seu filho confirmou a escala' ELSE 'Seu filho desmarcou a escala' END,
    coalesce(v_name,'O coroinha')||CASE WHEN NEW.status='confirmado' THEN ' confirmou participação em ' ELSE ' desmarcou a participação em ' END||v_mass.title||'.',
    CASE WHEN NEW.status='confirmado' THEN 'parent_confirmations' ELSE 'parent_withdrawals' END
   FROM public.parent_child_links l JOIN public.profiles p ON p.id=l.parent_id AND p.approved AND p.role='pai'
   WHERE l.child_id=NEW.server_id;
  END IF;
 END IF;
 RETURN NEW;
END $fn$;

CREATE OR REPLACE FUNCTION public.respond_assignment(p_id uuid,p_action text,p_reason text DEFAULT '') RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $fn$
DECLARE v public.assignments%rowtype; t timestamptz;
BEGIN
 IF p_action='confirmar' AND NOT public.has_site_permission('confirm_assignment') THEN RAISE EXCEPTION 'Sem permissão para confirmar escala' USING ERRCODE='42501'; END IF;
 IF p_action='desmarcar' AND NOT public.has_site_permission('unassign_self') THEN RAISE EXCEPTION 'Sem permissão para desmarcar escala' USING ERRCODE='42501'; END IF;
 IF auth.uid() IS NULL OR NOT public.is_approved() THEN RAISE EXCEPTION 'Cadastro aguardando aprovação'; END IF;
 SELECT * INTO v FROM public.assignments WHERE id=p_id AND server_id=auth.uid() FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Escala não encontrada para sua conta'; END IF;
 SELECT starts_at INTO t FROM public.masses WHERE id=v.mass_id;
 IF t IS NULL THEN RAISE EXCEPTION 'Missa não encontrada'; END IF;
 IF p_action='desmarcar' THEN
  IF length(trim(coalesce(p_reason,'')))<3 THEN RAISE EXCEPTION 'Informe uma justificativa com pelo menos 3 caracteres'; END IF;
  IF v.status IN ('desmarcado','faltou','presente') THEN RAISE EXCEPTION 'Esta escala não permite desistência'; END IF;
  UPDATE public.assignments SET status='desmarcado',reason=trim(p_reason) WHERE id=p_id;
  IF t>now() THEN
   INSERT INTO public.notifications(user_id,title,body,event_key)
   SELECT p.id,'Vaga para substituição','Função: '||v.function_name||' • '||
    to_char(t AT TIME ZONE 'America/Sao_Paulo','DD/MM/YYYY HH24:MI'),
    CASE WHEN p.role='desenvolvedor' THEN 'developer_system'
         WHEN p.role='coordenadora' THEN 'coord_responses'
         WHEN v.service_group='cerimoniario' THEN 'ceremony_substitutes' ELSE 'server_substitutes' END
   FROM public.profiles p WHERE p.approved AND p.id<>auth.uid() AND
    (p.role='desenvolvedor' OR
     (p.role='coordenadora' AND p.coordination_group=v.service_group) OR
     p.role=v.service_group);
  END IF;
 ELSIF p_action='confirmar' THEN
  IF (t AT TIME ZONE 'America/Sao_Paulo')::date<>(now() AT TIME ZONE 'America/Sao_Paulo')::date OR t<=now() THEN
   RAISE EXCEPTION 'Confirmação disponível somente no dia da missa, antes de começar'; END IF;
  IF v.status NOT IN ('escalado','confirmado') THEN RAISE EXCEPTION 'Esta escala não pode ser confirmada'; END IF;
  UPDATE public.assignments SET status='confirmado' WHERE id=p_id;
 ELSE RAISE EXCEPTION 'Ação inválida';
 END IF;
END $fn$;

CREATE OR REPLACE FUNCTION public.notify_coordinator_message() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $fn$
DECLARE v_group text; v_name text;
BEGIN
 IF NOT public.automation_enabled('notify_coordinator_messages') THEN RETURN NEW; END IF;
 SELECT CASE WHEN role='cerimoniario' THEN 'cerimoniario' ELSE 'coroinha' END,
  coalesce(nullif(trim(name),''),'Integrante') INTO v_group,v_name FROM public.profiles WHERE id=NEW.user_id;
 INSERT INTO public.notifications(user_id,title,body,event_key)
 SELECT p.id,CASE WHEN NEW.type='reclamacao' THEN 'Nova reclamação' ELSE 'Nova sugestão' END,
 v_name||' enviou uma mensagem. Abra Mensagens.','coord_messages'
 FROM public.profiles p WHERE p.approved AND p.role='coordenadora' AND p.coordination_group=v_group;
 RETURN NEW;
END $fn$;

CREATE OR REPLACE FUNCTION public.notify_service_request() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $fn$
DECLARE v_mass public.masses%rowtype;v_name text;
BEGIN
 IF NOT public.automation_enabled('notify_service_requests') OR (TG_OP='UPDATE' AND OLD.status=NEW.status) THEN RETURN NEW; END IF;
 SELECT * INTO v_mass FROM public.masses WHERE id=NEW.mass_id;
 SELECT name INTO v_name FROM public.profiles WHERE id=NEW.user_id;
 INSERT INTO public.notifications(user_id,title,body,event_key)
 SELECT p.id,'Nova solicitação para servir',
 coalesce(v_name,'Um integrante')||' solicitou servir em '||
 to_char(v_mass.starts_at AT TIME ZONE 'America/Sao_Paulo','DD/MM/YYYY HH24:MI')||'.',
 CASE WHEN p.role='desenvolvedor' THEN 'developer_system' ELSE 'coord_requests' END
 FROM public.profiles p WHERE p.approved AND (p.role='desenvolvedor' OR (p.role='coordenadora' AND p.coordination_group=NEW.service_group));
 RETURN NEW;
END $fn$;
