-- 087: Flexibilidade somente quando existe permissão no catálogo.
-- Cargos permanecem inalterados; o Desenvolvedor concede explicitamente direitos de servir.
INSERT INTO public.permission_catalog(key,category,label,default_roles,sensitive)
VALUES ('eligible_to_serve','Coroinhas e cerimoniários','Ser selecionado e escalado para servir',ARRAY['coroinha','cerimoniario']::text[],false)
ON CONFLICT(key) DO UPDATE SET category=excluded.category,label=excluded.label,default_roles=excluded.default_roles;

CREATE OR REPLACE FUNCTION public.user_has_catalog_permission(p_user uuid,p_key text)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE p public.profiles%rowtype;c public.permission_catalog%rowtype;v_allowed boolean;v_role text;
BEGIN
 SELECT * INTO p FROM public.profiles WHERE id=p_user AND approved;
 IF NOT FOUND THEN RETURN false; END IF;
 SELECT * INTO c FROM public.permission_catalog WHERE key=p_key;
 IF NOT FOUND THEN RETURN false; END IF;
 SELECT allowed INTO v_allowed FROM public.permission_rules
 WHERE subject_user=p_user AND permission_key=p_key AND (expires_at IS NULL OR expires_at>now())
 ORDER BY created_at DESC,id DESC LIMIT 1;
 IF FOUND THEN RETURN v_allowed; END IF;
 v_role:=CASE WHEN p.role='coordenadora' THEN 'coordenadora_'||coalesce(p.coordination_group,'coroinha') ELSE p.role END;
 SELECT allowed INTO v_allowed FROM public.permission_rules WHERE subject_role=v_role AND permission_key=p_key
 AND (expires_at IS NULL OR expires_at>now()) ORDER BY created_at DESC,id DESC LIMIT 1;
 IF FOUND THEN RETURN v_allowed; END IF;
 IF v_role<>p.role THEN
  SELECT allowed INTO v_allowed FROM public.permission_rules WHERE subject_role=p.role AND permission_key=p_key
  AND (expires_at IS NULL OR expires_at>now()) ORDER BY created_at DESC,id DESC LIMIT 1;
  IF FOUND THEN RETURN v_allowed; END IF;
 END IF;
 IF p.role='desenvolvedor' THEN
  RETURN p_key NOT IN ('choose_theme','request_service','eligible_to_serve','confirm_assignment','unassign_self','send_suggestions','vote_polls','view_child_scales');
 END IF;
 RETURN p.role=ANY(c.default_roles) OR v_role=ANY(c.default_roles);
END $function$;

CREATE OR REPLACE FUNCTION public.is_eligible_service_member(p_user uuid,p_group text)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_role text;
BEGIN
 IF p_group NOT IN ('coroinha','cerimoniario') OR p_user IS NULL THEN RETURN false; END IF;
 SELECT role INTO v_role FROM public.profiles WHERE id=p_user AND approved;
 IF NOT FOUND THEN RETURN false; END IF;
 IF v_role=p_group THEN
  RETURN public.user_has_catalog_permission(p_user,'eligible_to_serve') OR public.user_has_catalog_permission(p_user,'request_service');
 END IF;
 -- Noutros cargos, SOMENTE permissão explícita, individual ou do perfil.
 RETURN EXISTS(SELECT 1 FROM public.permission_rules r WHERE r.permission_key IN ('request_service','eligible_to_serve')
  AND r.allowed AND (r.expires_at IS NULL OR r.expires_at>now()) AND
  (r.subject_user=p_user OR r.subject_role=v_role OR (v_role='coordenadora' AND r.subject_role=
   (SELECT 'coordenadora_'||coordination_group FROM public.profiles WHERE id=p_user))))
  AND (public.user_has_catalog_permission(p_user,'request_service') OR public.user_has_catalog_permission(p_user,'eligible_to_serve'));
END $function$;

CREATE OR REPLACE FUNCTION public.service_candidate_list(p_group text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
BEGIN
 IF p_group NOT IN ('coroinha','cerimoniario') THEN RAISE EXCEPTION 'Grupo inválido' USING ERRCODE='22023'; END IF;
 IF NOT (public.has_site_permission('create_scales') OR public.can_manage_service_group(p_group)
  OR public.has_site_permission('approve_requests')) THEN RAISE EXCEPTION 'Sem permissão para consultar integrantes' USING ERRCODE='42501'; END IF;
 RETURN coalesce((SELECT jsonb_agg(p.id ORDER BY p.name) FROM public.profiles p
 WHERE p.approved AND public.is_eligible_service_member(p.id,p_group)),'[]'::jsonb);
END $function$;

REVOKE ALL ON FUNCTION public.user_has_catalog_permission(uuid,text) FROM PUBLIC,coroinhas_app;
REVOKE ALL ON FUNCTION public.is_eligible_service_member(uuid,text) FROM PUBLIC,coroinhas_app;
REVOKE ALL ON FUNCTION public.service_candidate_list(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.service_candidate_list(text) TO coroinhas_app;
