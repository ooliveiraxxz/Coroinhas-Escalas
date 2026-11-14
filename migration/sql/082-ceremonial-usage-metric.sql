-- Adds an approved Cerimoniário count while preserving the existing permission guard and metrics.
CREATE OR REPLACE FUNCTION public.developer_usage_summary()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
 IF NOT public.has_site_permission('view_developer_panel') THEN RAISE EXCEPTION 'Sem permissão para esta ação' USING ERRCODE='42501'; END IF;

 -- Access controlled by view_developer_panel permission.
 RETURN jsonb_build_object(
 'total_users',(SELECT count(*) FROM public.profiles),
 'approved_users',(SELECT count(*) FROM public.profiles WHERE approved),
 'pending_users',(SELECT count(*) FROM public.profiles WHERE NOT approved),
 'servers',(SELECT count(*) FROM public.profiles WHERE role='coroinha' AND approved),
 'ceremoniaries',(SELECT count(*) FROM public.profiles WHERE role='cerimoniario' AND approved),
 'parents',(SELECT count(*) FROM public.profiles WHERE role='pai' AND approved),
 'coordinators',(SELECT count(*) FROM public.profiles WHERE role='coordenadora' AND approved),
 'developers',(SELECT count(*) FROM public.profiles WHERE role='desenvolvedor' AND approved),
 'active_24h',(SELECT count(*) FROM public.profiles WHERE last_seen_at >= now()-interval '24 hours'),
 'logins_recorded',(SELECT count(*) FROM public.login_events),
 'db_size_bytes',pg_database_size(current_database()),
 'masses',(SELECT count(*) FROM public.masses),
 'notifications',(SELECT count(*) FROM public.notifications));
END $function$
