-- Corrige o painel Últimos acessos por perfil para aceitar Cerimoniários.
-- Mantém a verificação de permissão do desenvolvedor e os demais perfis.

CREATE OR REPLACE FUNCTION public.developer_recent_access(p_role text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
 IF NOT public.has_site_permission('view_developer_panel') THEN RAISE EXCEPTION 'Sem permissão para esta ação' USING ERRCODE='42501'; END IF;

 -- Access controlled by view_developer_panel permission.
 IF p_role IS NULL OR p_role NOT IN ('coroinha','cerimoniario','pai','coordenadora') THEN
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
