-- Legacy Mensagens was replaced with Chat Rápido. Keep historical data/rules untouched.
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
  (p.role='desenvolvedor' AND c.key NOT IN ('choose_theme','request_service','eligible_to_serve','confirm_assignment','unassign_self','send_suggestions','vote_polls','view_child_scales')) OR p.role=ANY(c.default_roles) OR (p.role='coordenadora' AND ('coordenadora_'||coalesce(p.coordination_group,'coroinha'))=ANY(c.default_roles))),
  'default',(p.role='desenvolvedor' AND c.key NOT IN ('choose_theme','request_service','eligible_to_serve','confirm_assignment','unassign_self','send_suggestions','vote_polls','view_child_scales')) OR p.role=ANY(c.default_roles) OR (p.role='coordenadora' AND ('coordenadora_'||coalesce(p.coordination_group,'coroinha'))=ANY(c.default_roles)),
  'sensitive',c.sensitive) ORDER BY c.category,c.label) FROM public.permission_catalog c WHERE c.key NOT IN ('view_messages','mark_messages_seen')),'[]'::jsonb);
END $function$;
