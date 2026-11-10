-- Permissões configuráveis (roles e usuários), sem alterar padrões existentes.
CREATE TABLE IF NOT EXISTS public.permission_rules (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 subject_role text,
 subject_user uuid REFERENCES public.profiles(id) ON DELETE CASCADE,
 permission_key text NOT NULL CHECK(permission_key IN ('edit_coroinha','edit_cerimoniario','view_audit')),
 allowed boolean NOT NULL,
 expires_at timestamptz,
 created_by uuid REFERENCES public.profiles(id),
 created_at timestamptz NOT NULL DEFAULT now(),
 CONSTRAINT exactly_one_subject CHECK ((subject_role IS NOT NULL)<>(subject_user IS NOT NULL))
);
ALTER TABLE public.permission_rules ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.permission_rules FROM PUBLIC,coroinhas_app,coroinhas_gateway;

CREATE OR REPLACE FUNCTION public.can_manage_service_group(p_group text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$ SELECT CASE WHEN p_group='coroinha' THEN public.has_site_permission('edit_coroinha') WHEN p_group='cerimoniario' THEN public.has_site_permission('edit_cerimoniario') ELSE false END $function$
;

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
END $function$
;

CREATE OR REPLACE FUNCTION public.developer_list_permission_rules()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$ BEGIN IF NOT public.is_developer() THEN RAISE EXCEPTION 'Acesso restrito' USING ERRCODE='42501'; END IF; RETURN coalesce((SELECT jsonb_agg(to_jsonb(r) ORDER BY r.created_at DESC) FROM public.permission_rules r),'[]'::jsonb); END $function$
;

CREATE OR REPLACE FUNCTION public.developer_save_permission(p_permission text, p_role text, p_user uuid, p_allowed boolean, p_expires timestamp with time zone, p_confirmation text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_id uuid;
BEGIN
 IF NOT public.is_developer() OR trim(coalesce(p_confirmation,''))<>'DESENVOLVEDOR' THEN RAISE EXCEPTION 'Confirmação inválida' USING ERRCODE='42501'; END IF;
 IF p_permission NOT IN ('edit_coroinha','edit_cerimoniario','view_audit') OR p_allowed IS NULL OR ((p_role IS NULL)=(p_user IS NULL)) THEN RAISE EXCEPTION 'Permissão inválida' USING ERRCODE='22023'; END IF;
 IF p_role IS NOT NULL AND p_role NOT IN ('coroinha','cerimoniario','pai','coordenadora','coordenadora_coroinha','coordenadora_cerimoniario') THEN RAISE EXCEPTION 'Perfil inválido' USING ERRCODE='22023'; END IF;
 IF p_user IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.profiles WHERE id=p_user AND role<>'desenvolvedor') THEN RAISE EXCEPTION 'Usuário inválido' USING ERRCODE='42501'; END IF;
 IF p_expires IS NOT NULL AND (p_expires<=now() OR p_expires>now()+interval '365 days') THEN RAISE EXCEPTION 'Prazo inválido' USING ERRCODE='22023'; END IF;
 INSERT INTO public.permission_rules(subject_role,subject_user,permission_key,allowed,expires_at,created_by) VALUES(p_role,p_user,p_permission,p_allowed,p_expires,auth.uid()) RETURNING id INTO v_id;
 RETURN v_id;
END $function$
;

CREATE OR REPLACE FUNCTION public.developer_set_automation(p_enabled boolean, p_confirmation text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$ BEGIN IF NOT public.is_developer() OR trim(coalesce(p_confirmation,''))<>'DESENVOLVEDOR' THEN RAISE EXCEPTION 'Confirmação inválida' USING ERRCODE='42501'; END IF; UPDATE public.service_settings SET enabled=p_enabled,updated_at=now() WHERE key='auto_approval_3h'; RETURN p_enabled; END $function$
;

CREATE OR REPLACE FUNCTION public.has_site_permission(p_key text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE p public.profiles%rowtype; v_allowed boolean; v_role text;
BEGIN
 SELECT * INTO p FROM public.profiles WHERE id=auth.uid() AND approved;
 IF NOT FOUND OR p_key NOT IN ('edit_coroinha','edit_cerimoniario','view_audit') THEN RETURN false; END IF;
 IF p.role='desenvolvedor' THEN RETURN true; END IF;
 v_role:=CASE WHEN p.role='coordenadora' THEN 'coordenadora_'||coalesce(p.coordination_group,'coroinha') ELSE p.role END;
 SELECT allowed INTO v_allowed FROM public.permission_rules WHERE subject_user=p.id AND permission_key=p_key AND (expires_at IS NULL OR expires_at>now()) ORDER BY created_at DESC,id DESC LIMIT 1;
 IF FOUND THEN RETURN v_allowed; END IF;
 SELECT allowed INTO v_allowed FROM public.permission_rules WHERE subject_role=v_role AND permission_key=p_key AND (expires_at IS NULL OR expires_at>now()) ORDER BY created_at DESC,id DESC LIMIT 1;
 IF FOUND THEN RETURN v_allowed; END IF;
 SELECT allowed INTO v_allowed FROM public.permission_rules WHERE subject_role=p.role AND permission_key=p_key AND (expires_at IS NULL OR expires_at>now()) ORDER BY created_at DESC,id DESC LIMIT 1;
 IF FOUND THEN RETURN v_allowed; END IF;
 RETURN p.role='coordenadora' AND ((p_key='edit_coroinha' AND coalesce(p.coordination_group,'coroinha')='coroinha') OR (p_key='edit_cerimoniario' AND p.coordination_group='cerimoniario'));
END $function$
;

DROP TRIGGER IF EXISTS permission_rules_audit ON public.permission_rules;
CREATE TRIGGER permission_rules_audit AFTER INSERT OR UPDATE OR DELETE ON public.permission_rules FOR EACH ROW EXECUTE FUNCTION public.audit_record_change();
DROP POLICY IF EXISTS mass_update ON public.masses;
CREATE POLICY mass_update ON public.masses FOR UPDATE USING (public.is_developer() OR (public.is_coordinator() AND NOT EXISTS (SELECT 1 FROM public.assignments a WHERE a.mass_id=masses.id AND NOT public.can_manage_service_group(a.service_group)))) WITH CHECK (public.is_developer() OR (public.is_coordinator() AND NOT EXISTS (SELECT 1 FROM public.assignments a WHERE a.mass_id=masses.id AND NOT public.can_manage_service_group(a.service_group))));
REVOKE ALL ON FUNCTION public.developer_list_permission_rules(),public.developer_save_permission(text,text,uuid,boolean,timestamptz,text),public.developer_set_automation(boolean,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.developer_list_permission_rules(),public.developer_save_permission(text,text,uuid,boolean,timestamptz,text),public.developer_set_automation(boolean,text),public.has_site_permission(text) TO coroinhas_app,coroinhas_gateway;
