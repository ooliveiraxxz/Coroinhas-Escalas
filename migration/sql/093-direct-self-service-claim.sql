-- Somente homologação; executar em produção requer autorização expressa.
BEGIN;
CREATE OR REPLACE FUNCTION public.guard_delegated_assignment_update()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
BEGIN
 IF TG_OP<>'UPDATE' OR auth.uid() IS NULL OR public.can_manage_service_group(OLD.service_group) THEN
  RETURN NEW;
 END IF;
 -- Novo caminho restrito: o próprio integrante ocupa uma função aberta.
 IF OLD.server_id IS DISTINCT FROM NEW.server_id AND NEW.server_id=auth.uid()
 AND (OLD.server_id IS NULL OR OLD.status='desmarcado')
 AND NEW.status='escalado' AND NEW.reason IS NULL
 AND NEW.id IS NOT DISTINCT FROM OLD.id AND NEW.mass_id IS NOT DISTINCT FROM OLD.mass_id
 AND NEW.function_name IS NOT DISTINCT FROM OLD.function_name
 AND NEW.service_group IS NOT DISTINCT FROM OLD.service_group
 AND NEW.created_at IS NOT DISTINCT FROM OLD.created_at
 AND public.has_site_permission('request_service')
 AND public.is_eligible_service_member(auth.uid(),OLD.service_group)
 AND EXISTS(SELECT 1 FROM public.masses m WHERE m.id=OLD.mass_id
  AND m.published AND m.archived_at IS NULL AND m.starts_at>now())
 AND NOT EXISTS(SELECT 1 FROM public.assignments other
  WHERE other.mass_id=OLD.mass_id AND other.server_id=auth.uid()
  AND other.status<>'desmarcado' AND other.id<>OLD.id)
 THEN RETURN NEW; END IF;
 -- Approval permission authorizes exactly a pending request's open slot, not arbitrary reassignment.
 IF OLD.server_id IS DISTINCT FROM NEW.server_id
 AND (public.has_site_permission('approve_requests')
  OR (pg_trigger_depth()>1
   AND EXISTS(SELECT 1 FROM public.service_settings WHERE key='auto_approval_3h' AND enabled)
   AND EXISTS(SELECT 1 FROM public.masses m WHERE m.id=OLD.mass_id
      AND m.published AND m.starts_at>now() AND m.starts_at<=now()+interval '3 hours')))
 AND (OLD.server_id IS NULL OR OLD.status='desmarcado')
 AND NEW.server_id IS NOT NULL AND NEW.status='escalado' AND NEW.reason IS NULL
 AND NEW.id IS NOT DISTINCT FROM OLD.id AND NEW.mass_id IS NOT DISTINCT FROM OLD.mass_id
 AND NEW.function_name IS NOT DISTINCT FROM OLD.function_name
 AND NEW.service_group IS NOT DISTINCT FROM OLD.service_group
 AND NEW.created_at IS NOT DISTINCT FROM OLD.created_at
 AND EXISTS(SELECT 1 FROM public.requests r WHERE r.mass_id=OLD.mass_id
  AND r.user_id=NEW.server_id AND r.service_group=OLD.service_group AND r.status='pendente'
  AND ((r.type='servir' AND r.assignment_id IS NULL)
    OR (r.type='substituir' AND r.assignment_id=OLD.id))) THEN
  RETURN NEW;
 END IF;
 IF NEW.id IS DISTINCT FROM OLD.id OR NEW.mass_id IS DISTINCT FROM OLD.mass_id
 OR NEW.server_id IS DISTINCT FROM OLD.server_id OR NEW.function_name IS DISTINCT FROM OLD.function_name
 OR NEW.service_group IS DISTINCT FROM OLD.service_group OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
  RAISE EXCEPTION 'Sem permissão para editar integrantes ou funções da escala' USING ERRCODE='42501';
 END IF;
 IF NEW.status IS DISTINCT FROM OLD.status THEN
  IF NEW.status IN ('presente','faltou') AND public.has_site_permission('attendance') THEN RETURN NEW; END IF;
  IF NEW.status='confirmado' AND OLD.server_id=auth.uid() AND public.has_site_permission('confirm_assignment') THEN RETURN NEW; END IF;
  IF NEW.status='desmarcado' AND OLD.server_id=auth.uid() AND public.has_site_permission('unassign_self') THEN RETURN NEW; END IF;
  RAISE EXCEPTION 'Sem permissão para alterar o status da escala' USING ERRCODE='42501';
 END IF;
 IF NEW.reason IS DISTINCT FROM OLD.reason THEN
  RAISE EXCEPTION 'Sem permissão para alterar a justificativa' USING ERRCODE='42501';
 END IF;
 RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION public.claim_service_slot(p_assignment_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $claim$
DECLARE v_slot public.assignments%ROWTYPE; v_mass public.masses%ROWTYPE; v_user uuid;
BEGIN
 v_user:=auth.uid();
 IF v_user IS NULL OR NOT public.has_site_permission('request_service') THEN
  RAISE EXCEPTION 'Sem permissão para solicitar esta escala' USING ERRCODE='42501';
 END IF;
 SELECT * INTO v_slot FROM public.assignments WHERE id=p_assignment_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Função não encontrada'; END IF;
 SELECT * INTO v_mass FROM public.masses WHERE id=v_slot.mass_id FOR UPDATE;
 IF NOT FOUND OR v_mass.published IS NOT TRUE OR v_mass.archived_at IS NOT NULL OR v_mass.starts_at<=now() THEN
  RAISE EXCEPTION 'Missa indisponível para inscrição';
 END IF;
 IF NOT public.is_eligible_service_member(v_user,v_slot.service_group) THEN
  RAISE EXCEPTION 'Seu perfil não pode servir nesta função' USING ERRCODE='42501';
 END IF;
 IF v_slot.server_id IS NOT NULL AND v_slot.status<>'desmarcado' THEN
  RAISE EXCEPTION 'Esta função já foi ocupada';
 END IF;
 IF v_slot.server_id=v_user THEN RAISE EXCEPTION 'Você já ocupou esta função'; END IF;
 IF EXISTS (SELECT 1 FROM public.assignments x WHERE x.mass_id=v_slot.mass_id
  AND x.server_id=v_user AND x.status<>'desmarcado') THEN
  RAISE EXCEPTION 'Você já está escalado nesta missa';
 END IF;
 UPDATE public.assignments SET server_id=v_user,status='escalado',reason=NULL WHERE id=p_assignment_id;
 INSERT INTO public.notifications(user_id,title,body,event_key)
 VALUES(v_user,'Você foi escalado!','Sua função '||v_slot.function_name||' foi reservada para '||
 to_char(v_mass.starts_at AT TIME ZONE 'America/Sao_Paulo','DD/MM/YYYY HH24:MI')||'.','service_approved');
END $claim$;
REVOKE ALL ON FUNCTION public.claim_service_slot(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.claim_service_slot(uuid) TO coroinhas_app;
COMMIT;
