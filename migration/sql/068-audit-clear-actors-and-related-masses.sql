-- Enrich developer-only audit without modifying evidence: actor names and related celebration titles.
CREATE OR REPLACE FUNCTION public.developer_audit_recent()
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $fn$
BEGIN
 IF NOT public.has_site_permission('view_audit') THEN RAISE EXCEPTION 'Sem permissão para consultar auditoria' USING ERRCODE='42501'; END IF;
 RETURN coalesce((SELECT jsonb_agg(to_jsonb(a) ORDER BY a.happened_at DESC,a.id DESC)
  FROM (
   SELECT l.id,l.happened_at,l.actor_id,l.actor_email,
    coalesce(nullif(trim(p.name),''),
      (SELECT nullif(trim(x.after_data->>'name'),'') FROM public.audit_log x
       WHERE x.table_name='profiles' AND x.record_id=l.actor_id::text
         AND x.after_data ? 'name' AND x.after_data->>'name'<>''
       ORDER BY x.id DESC LIMIT 1)) AS actor_name,
    l.table_name,l.action,l.record_id,l.before_data,l.after_data,
    CASE WHEN l.table_name IN ('assignments','requests') THEN
      coalesce(
       (SELECT m.title FROM public.masses m
        WHERE m.id::text=coalesce(l.after_data->>'mass_id',l.before_data->>'mass_id') LIMIT 1),
       (SELECT coalesce(x.after_data->>'title',x.before_data->>'title')
        FROM public.audit_log x WHERE x.table_name='masses'
         AND x.record_id=coalesce(l.after_data->>'mass_id',l.before_data->>'mass_id')
        ORDER BY x.id DESC LIMIT 1))
     ELSE NULL END AS related_mass_name
   FROM public.audit_log l LEFT JOIN public.profiles p ON p.id=l.actor_id
   ORDER BY l.happened_at DESC,l.id DESC LIMIT 250
  ) a),'[]'::jsonb);
END $fn$;
