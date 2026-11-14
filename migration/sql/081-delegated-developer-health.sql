-- Permite apenas consultar a saúde do Neon quando a permissão view_developer_panel foi concedida.
-- Executar em homologação antes da produção. Não confere manage_users nem outras permissões.
CREATE OR REPLACE FUNCTION public.developer_neon_health()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_bytes bigint;v_conn int;v_deadlocks bigint;v_old record;v_tables jsonb;v_snapshots jsonb;v_quota bigint:=1073741824;
BEGIN
 IF NOT public.has_site_permission('view_developer_panel') THEN RAISE EXCEPTION 'Sem permissão para visualizar o Painel do Desenvolvedor' USING ERRCODE='42501'; END IF;
 SELECT pg_database_size(current_database()) INTO v_bytes;
 SELECT numbackends,deadlocks INTO v_conn,v_deadlocks FROM pg_stat_database WHERE datname=current_database();
 SELECT recorded_at,db_bytes INTO v_old FROM public.system_health_snapshots WHERE recorded_at<=now()-interval '1 day' ORDER BY recorded_at DESC LIMIT 1;
 SELECT coalesce(jsonb_agg(jsonb_build_object('name',name,'bytes',bytes) ORDER BY bytes DESC),'[]'::jsonb)
 INTO v_tables FROM (
  SELECT n.nspname||'.'||c.relname name,pg_total_relation_size(c.oid) bytes
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE c.relkind IN ('r','p') AND n.nspname IN ('public','neon_auth')
  ORDER BY pg_total_relation_size(c.oid) DESC LIMIT 12
 ) t;
 SELECT coalesce(jsonb_agg(jsonb_build_object('date',recorded_at,'bytes',db_bytes) ORDER BY recorded_at),'[]'::jsonb)
 INTO v_snapshots FROM (SELECT recorded_at,db_bytes FROM public.system_health_snapshots ORDER BY recorded_at DESC LIMIT 30) s;
 RETURN jsonb_build_object(
  'sampled_at',now(),'database','coroinhas',
  'db_bytes',v_bytes,'reference_limit_bytes',v_quota,'reference_kind','Limite lógico informado pelo projeto Neon; o tamanho PostgreSQL não é equivalente ao consumo faturado.',
  'used_pct_reference',round(100*v_bytes::numeric/v_quota,2),
  'capacity_score',greatest(0,round(100-100*v_bytes::numeric/v_quota,1)),
  'connections',coalesce(v_conn,0),'deadlocks_total',coalesce(v_deadlocks,0),
  'previous_date',v_old.recorded_at,'previous_bytes',v_old.db_bytes,
  'estimated_days_to_limit',CASE WHEN v_old.db_bytes IS NOT NULL AND v_bytes>v_old.db_bytes AND v_bytes<v_quota
   THEN ceil((v_quota-v_bytes)::numeric / ((v_bytes-v_old.db_bytes)::numeric / greatest(extract(epoch from now()-v_old.recorded_at)/86400,0.01))) ELSE NULL END,
  'top_tables',v_tables,'history',v_snapshots
 );
END $function$
;
