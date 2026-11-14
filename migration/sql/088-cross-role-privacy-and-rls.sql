-- 088: Enforce the exact catalogued rights at the data boundary (no developer role bypass).
DROP POLICY IF EXISTS requests_insert ON public.requests;
CREATE POLICY requests_insert ON public.requests FOR INSERT TO coroinhas_app WITH CHECK (
 public.has_site_permission('request_service') AND status='pendente' AND user_id=auth.uid()
 AND public.is_approved() AND public.is_eligible_service_member(user_id,service_group)
 AND EXISTS(SELECT 1 FROM public.masses m WHERE m.id=requests.mass_id AND m.published AND m.starts_at>now())
 AND (
  (type='servir' AND assignment_id IS NULL AND EXISTS
   (SELECT 1 FROM public.assignments a WHERE a.mass_id=requests.mass_id
    AND a.service_group=requests.service_group AND (a.server_id IS NULL OR a.status='desmarcado')))
  OR (type='substituir' AND assignment_id IS NOT NULL AND EXISTS
   (SELECT 1 FROM public.assignments a WHERE a.id=requests.assignment_id
    AND a.mass_id=requests.mass_id AND a.service_group=requests.service_group AND a.status='desmarcado'
    AND a.server_id IS DISTINCT FROM auth.uid()))
 )
 AND NOT EXISTS(SELECT 1 FROM public.assignments a WHERE a.mass_id=requests.mass_id AND a.server_id=auth.uid()
 AND a.status<>'desmarcado')
);

-- Parents see the linked child's masses only unless the developer explicitly grants full view_scales.
CREATE OR REPLACE FUNCTION public.can_read_mass_for_user(p_mass uuid)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE p public.profiles%rowtype;v_override boolean;
BEGIN
 SELECT * INTO p FROM public.profiles WHERE id=auth.uid() AND approved;
 IF NOT FOUND THEN RETURN false; END IF;
 -- A delegated servant may always access their OWN assignment to confirm or unassign.
 IF (public.has_site_permission('confirm_assignment') OR public.has_site_permission('unassign_self'))
 AND EXISTS(SELECT 1 FROM public.assignments a WHERE a.mass_id=p_mass AND a.server_id=p.id
   AND a.status IN ('escalado','confirmado')) THEN RETURN true; END IF;
 -- Every independently delegated operation must be able to read the masses it acts on.
 IF public.has_site_permission('attendance') OR public.has_site_permission('approve_requests')
 OR public.has_site_permission('create_scales') OR public.has_site_permission('delete_scales')
 OR public.has_site_permission('edit_coroinha') OR public.has_site_permission('edit_cerimoniario')
 OR public.has_site_permission('view_reports') THEN RETURN true; END IF;
 IF public.has_site_permission('request_service') AND EXISTS(
  SELECT 1 FROM public.assignments a WHERE a.mass_id=p_mass AND (a.server_id IS NULL OR a.status='desmarcado')
  AND public.is_eligible_service_member(p.id,a.service_group)
 ) THEN RETURN true; END IF;
 IF NOT public.has_site_permission('view_scales') THEN RETURN false; END IF;
 IF p.role<>'pai' THEN RETURN true; END IF;
 SELECT allowed INTO v_override FROM public.permission_rules
 WHERE subject_user=p.id AND permission_key='view_scales'
 AND (expires_at IS NULL OR expires_at>now()) ORDER BY created_at DESC,id DESC LIMIT 1;
 IF v_override IS TRUE THEN RETURN true; END IF;
 IF NOT public.has_site_permission('view_child_scales') THEN RETURN false; END IF;
 RETURN EXISTS(SELECT 1 FROM public.parent_child_links l
 JOIN public.assignments a ON a.server_id=l.child_id
 WHERE l.parent_id=p.id AND a.mass_id=p_mass AND a.status<>'desmarcado');
END $function$;
REVOKE ALL ON FUNCTION public.can_read_mass_for_user(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.can_read_mass_for_user(uuid) TO coroinhas_app;

DROP POLICY IF EXISTS mass_read ON public.masses;
CREATE POLICY mass_read ON public.masses FOR SELECT TO coroinhas_app USING (
 archived_at IS NULL AND starts_at>now()-interval '24 hours'
 AND published AND public.can_read_mass_for_user(id)
);
-- A parent can only read the linked child's assigned lines plus open slots when allowed to serve.
CREATE OR REPLACE FUNCTION public.can_read_assignment_for_user(p_mass uuid,p_server uuid,p_group text,p_status text)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE p public.profiles%rowtype;v_override boolean;
BEGIN
 IF NOT public.can_read_mass_for_user(p_mass) THEN RETURN false; END IF;
 SELECT * INTO p FROM public.profiles WHERE id=auth.uid() AND approved;
 IF NOT FOUND THEN RETURN false; END IF;
 IF p_server=p.id AND (public.has_site_permission('confirm_assignment') OR public.has_site_permission('unassign_self')) THEN RETURN true; END IF;
 IF public.has_site_permission('attendance') OR public.has_site_permission('approve_requests')
 OR public.has_site_permission('create_scales') OR public.has_site_permission('delete_scales')
 OR public.has_site_permission('edit_coroinha') OR public.has_site_permission('edit_cerimoniario')
 OR public.has_site_permission('view_reports') THEN RETURN true; END IF;
 IF p.role='pai' THEN
  SELECT allowed INTO v_override FROM public.permission_rules WHERE subject_user=p.id
  AND permission_key='view_scales' AND (expires_at IS NULL OR expires_at>now())
  ORDER BY created_at DESC,id DESC LIMIT 1;
  IF v_override IS TRUE THEN RETURN true; END IF;
  IF p_server IS NOT NULL AND public.has_site_permission('view_child_scales') AND EXISTS(
   SELECT 1 FROM public.parent_child_links l WHERE l.parent_id=p.id AND l.child_id=p_server
  ) THEN RETURN true; END IF;
  RETURN public.has_site_permission('request_service') AND (p_server IS NULL OR p_status='desmarcado')
   AND public.is_eligible_service_member(p.id,p_group);
 END IF;
 IF public.has_site_permission('view_scales') THEN RETURN true; END IF;
 RETURN public.has_site_permission('request_service') AND (p_server IS NULL OR p_status='desmarcado')
  AND public.is_eligible_service_member(p.id,p_group);
END $function$;
REVOKE ALL ON FUNCTION public.can_read_assignment_for_user(uuid,uuid,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.can_read_assignment_for_user(uuid,uuid,text,text) TO coroinhas_app;

DROP POLICY IF EXISTS assignment_read ON public.assignments;
CREATE POLICY assignment_read ON public.assignments FOR SELECT TO coroinhas_app USING (
 public.can_read_assignment_for_user(mass_id,server_id,service_group,status)
 AND EXISTS (SELECT 1 FROM public.masses m WHERE m.id=assignments.mass_id AND m.published
 AND m.archived_at IS NULL AND m.starts_at>now()-interval '24 hours')
);
DROP POLICY IF EXISTS notes_read ON public.notifications;
CREATE POLICY notes_read ON public.notifications FOR SELECT TO coroinhas_app USING (
 archived_at IS NULL
 AND ((user_id=auth.uid() AND public.has_site_permission('read_notifications'))
 OR (created_by=auth.uid() AND public.has_site_permission('send_notifications')))
);

-- SECURITY DEFINER avoids policy recursion when examining groups assigned to one mass.
CREATE OR REPLACE FUNCTION public.can_update_mass_as_actor(p_mass uuid)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
BEGIN
 IF NOT (public.has_site_permission('edit_coroinha')
 OR public.has_site_permission('edit_cerimoniario')) THEN RETURN false; END IF;
 -- Creating scales alone does not give editing rights for existing scales.
 -- Developer role may not bypass an individual deny on either service group.
 RETURN NOT EXISTS(SELECT 1 FROM public.assignments a WHERE a.mass_id=p_mass
 AND NOT public.can_manage_service_group(a.service_group));
END $function$;
REVOKE ALL ON FUNCTION public.can_update_mass_as_actor(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.can_update_mass_as_actor(uuid) TO coroinhas_app;

DROP POLICY IF EXISTS mass_update ON public.masses;
CREATE POLICY mass_update ON public.masses FOR UPDATE TO coroinhas_app USING (
 archived_at IS NULL AND starts_at>now()-interval '24 hours' AND public.can_update_mass_as_actor(id)
) WITH CHECK (
 archived_at IS NULL AND starts_at>now()-interval '24 hours' AND public.can_update_mass_as_actor(id)
);

-- A separately granted delete_scales right does not silently require edit_coroinha/edit_cerimoniario.
DROP POLICY IF EXISTS mass_delete ON public.masses;
CREATE POLICY mass_delete ON public.masses FOR DELETE TO coroinhas_app USING (
 archived_at IS NULL AND starts_at>now()-interval '24 hours'
 AND public.has_site_permission('delete_scales')
);
