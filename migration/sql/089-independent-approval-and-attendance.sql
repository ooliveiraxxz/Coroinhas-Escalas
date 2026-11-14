-- 089: A permission works as a complete operation without requiring another role.
-- Approval authorization is independent from editing the group's entire scale.
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
 -- A permissão approve_requests, por si só, autoriza aprovar vagas dos dois grupos.
 SELECT * INTO a FROM public.assignments WHERE id=p_assignment_id FOR UPDATE;
 IF NOT FOUND OR a.mass_id<>r.mass_id OR a.service_group<>r.service_group THEN RAISE EXCEPTION 'Vaga incompatível com a solicitação'; END IF;
 SELECT starts_at INTO v_time FROM public.masses WHERE id=r.mass_id;
 IF v_time IS NULL OR v_time<=now() THEN RAISE EXCEPTION 'Missa já iniciada'; END IF;
 IF a.server_id IS NOT NULL AND a.status<>'desmarcado' THEN RAISE EXCEPTION 'Vaga ocupada'; END IF;
 IF r.type='substituir' AND (r.assignment_id IS DISTINCT FROM a.id OR a.status<>'desmarcado') THEN RAISE EXCEPTION 'Vaga de substituição inválida'; END IF;
 IF NOT EXISTS(SELECT 1 WHERE public.is_eligible_service_member(r.user_id,r.service_group)) THEN
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

DROP POLICY IF EXISTS requests_read ON public.requests;
CREATE POLICY requests_read ON public.requests FOR SELECT TO coroinhas_app USING (
 EXISTS(SELECT 1 FROM public.masses m WHERE m.id=requests.mass_id AND m.archived_at IS NULL
 AND m.starts_at>now()-interval '24 hours')
 AND (user_id=auth.uid() OR public.has_site_permission('approve_requests')
 OR public.can_manage_service_group(service_group))
);
DROP POLICY IF EXISTS requests_manage ON public.requests;
CREATE POLICY requests_manage ON public.requests FOR UPDATE TO coroinhas_app USING (
 public.has_site_permission('approve_requests')
 AND EXISTS(SELECT 1 FROM public.masses m WHERE m.id=requests.mass_id AND m.archived_at IS NULL
 AND m.starts_at>now()-interval '24 hours')
) WITH CHECK (
 public.has_site_permission('approve_requests')
 AND EXISTS(SELECT 1 FROM public.masses m WHERE m.id=requests.mass_id AND m.archived_at IS NULL
 AND m.starts_at>now()-interval '24 hours')
);

-- Attendance is independently delegable; a narrow trigger forbids reassigning people
-- or editing functions through this weaker permission.
CREATE OR REPLACE FUNCTION public.guard_delegated_assignment_update()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
BEGIN
 IF TG_OP<>'UPDATE' OR auth.uid() IS NULL OR public.can_manage_service_group(OLD.service_group) THEN
  RETURN NEW;
 END IF;
 -- Approval permission authorizes exactly a pending request's open slot, not arbitrary reassignment.
 IF OLD.server_id IS DISTINCT FROM NEW.server_id
 AND (public.has_site_permission('approve_requests')
  OR (pg_trigger_depth()>1
   AND EXISTS(SELECT 1 FROM public.service_settings WHERE key='auto_approval_3h' AND enabled)
   AND EXISTS(SELECT 1 FROM public.masses m WHERE m.id=OLD.mass_id
      AND m.published AND m.starts_at>now() AND m.starts_at<=now()+interval '3 hours')))
 AND (OLD.server_id IS NULL OR OLD.status='desmarcado')
 AND NEW.server_id IS NOT NULL AND NEW.status='escalado' AND NEW.reason IS NULL
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
DROP TRIGGER IF EXISTS guard_delegated_assignment_update_trg ON public.assignments;
CREATE TRIGGER guard_delegated_assignment_update_trg BEFORE UPDATE ON public.assignments
FOR EACH ROW EXECUTE FUNCTION public.guard_delegated_assignment_update();

DROP POLICY IF EXISTS assignment_attendance_update ON public.assignments;
CREATE POLICY assignment_attendance_update ON public.assignments FOR UPDATE TO coroinhas_app USING (
 public.has_site_permission('attendance')
 AND EXISTS(SELECT 1 FROM public.masses m WHERE m.id=assignments.mass_id AND m.archived_at IS NULL
 AND m.starts_at>now()-interval '24 hours')
) WITH CHECK (
 public.has_site_permission('attendance')
 AND EXISTS(SELECT 1 FROM public.masses m WHERE m.id=assignments.mass_id AND m.archived_at IS NULL
 AND m.starts_at>now()-interval '24 hours')
);
