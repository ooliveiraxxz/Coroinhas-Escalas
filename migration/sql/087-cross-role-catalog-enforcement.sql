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
REVOKE ALL ON FUNCTION public.is_eligible_service_member(uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_eligible_service_member(uuid,text) TO coroinhas_app;
REVOKE ALL ON FUNCTION public.service_candidate_list(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.service_candidate_list(text) TO coroinhas_app;

-- Current user's allowed service groups. The UI never guesses them from the theme or role.
CREATE OR REPLACE FUNCTION public.my_service_groups()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
BEGIN
 IF auth.uid() IS NULL OR NOT public.is_approved() THEN RETURN '[]'::jsonb; END IF;
 RETURN coalesce((SELECT jsonb_agg(g.name ORDER BY g.name) FROM
 (VALUES ('coroinha'),('cerimoniario')) AS g(name)
 WHERE public.is_eligible_service_member(auth.uid(),g.name)),'[]'::jsonb);
END $function$;
REVOKE ALL ON FUNCTION public.my_service_groups() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.my_service_groups() TO coroinhas_app;


-- Existing guarded operations now recognize catalogued eligibility:
CREATE OR REPLACE FUNCTION public.has_site_permission(p_key text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE p public.profiles%rowtype; c public.permission_catalog%rowtype; v_allowed boolean; v_role text;
BEGIN
 SELECT * INTO p FROM public.profiles WHERE id=auth.uid() AND approved;
 IF NOT FOUND THEN RETURN false; END IF;

 IF p_key='choose_theme' THEN
  SELECT allowed INTO v_allowed FROM public.permission_rules WHERE subject_user=p.id AND permission_key=p_key AND (expires_at IS NULL OR expires_at>now()) ORDER BY created_at DESC,id DESC LIMIT 1;
  IF FOUND THEN RETURN v_allowed; END IF;
  v_role:=CASE WHEN p.role='coordenadora' THEN 'coordenadora_'||coalesce(p.coordination_group,'coroinha') ELSE p.role END;
  SELECT allowed INTO v_allowed FROM public.permission_rules WHERE subject_role=v_role AND permission_key=p_key AND (expires_at IS NULL OR expires_at>now()) ORDER BY created_at DESC,id DESC LIMIT 1;
  IF FOUND THEN RETURN v_allowed; END IF;
  SELECT allowed INTO v_allowed FROM public.permission_rules WHERE subject_role=p.role AND permission_key=p_key AND (expires_at IS NULL OR expires_at>now()) ORDER BY created_at DESC,id DESC LIMIT 1;
  IF FOUND THEN RETURN v_allowed; END IF;
  RETURN false;
 END IF;
 IF p.role='desenvolvedor' THEN
  SELECT allowed INTO v_allowed FROM public.permission_rules
  WHERE subject_user=p.id AND permission_key=p_key AND (expires_at IS NULL OR expires_at>now())
  ORDER BY created_at DESC,id DESC LIMIT 1;
  IF FOUND THEN RETURN v_allowed; END IF;
  IF p_key IN ('request_service','eligible_to_serve','confirm_assignment','unassign_self','send_suggestions','vote_polls','view_child_scales') THEN RETURN false; END IF;
  RETURN EXISTS(SELECT 1 FROM public.permission_catalog WHERE key=p_key);
 END IF;
 SELECT * INTO c FROM public.permission_catalog WHERE key=p_key;
 IF NOT FOUND THEN RETURN false; END IF;
 v_role:=CASE WHEN p.role='coordenadora' THEN 'coordenadora_'||coalesce(p.coordination_group,'coroinha') ELSE p.role END;
 SELECT allowed INTO v_allowed FROM public.permission_rules WHERE subject_user=p.id AND permission_key=p_key AND (expires_at IS NULL OR expires_at>now()) ORDER BY created_at DESC,id DESC LIMIT 1;
 IF FOUND THEN RETURN v_allowed; END IF;
 SELECT allowed INTO v_allowed FROM public.permission_rules WHERE subject_role=v_role AND permission_key=p_key AND (expires_at IS NULL OR expires_at>now()) ORDER BY created_at DESC,id DESC LIMIT 1;
 IF FOUND THEN RETURN v_allowed; END IF;
 SELECT allowed INTO v_allowed FROM public.permission_rules WHERE subject_role=p.role AND permission_key=p_key AND (expires_at IS NULL OR expires_at>now()) ORDER BY created_at DESC,id DESC LIMIT 1;
 IF FOUND THEN RETURN v_allowed; END IF;
 RETURN p.role=ANY(c.default_roles) OR v_role=ANY(c.default_roles);
END $function$;

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
  'sensitive',c.sensitive) ORDER BY c.category,c.label) FROM public.permission_catalog c),'[]'::jsonb);
END $function$;

CREATE OR REPLACE FUNCTION public.guard_server_assignment()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
 IF TG_OP='UPDATE' AND NEW.server_id IS NOT DISTINCT FROM OLD.server_id THEN RETURN NEW; END IF;
 IF NEW.server_id IS NOT NULL AND NOT EXISTS(
 SELECT 1 WHERE public.is_eligible_service_member(NEW.server_id,NEW.service_group)
 ) THEN RAISE EXCEPTION 'Somente um integrante aprovado do grupo da vaga pode ser escalado.' USING ERRCODE='42501'; END IF;
 RETURN NEW; END $function$;

CREATE OR REPLACE FUNCTION public.validate_service_assignment()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
 DECLARE v_role text; BEGIN
 IF NEW.service_group NOT IN ('coroinha','cerimoniario') THEN RAISE EXCEPTION 'Grupo inválido'; END IF;
 IF NEW.server_id IS NOT NULL THEN
   SELECT role INTO v_role FROM public.profiles WHERE id=NEW.server_id AND approved;
   IF NOT public.is_eligible_service_member(NEW.server_id,NEW.service_group) THEN
      RAISE EXCEPTION 'O integrante não pertence ao grupo da vaga';
   END IF;
 END IF;
 RETURN NEW; END $function$;

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
 IF NOT public.can_manage_service_group(r.service_group) THEN RAISE EXCEPTION 'Coordenação de outro grupo' USING errcode='42501'; END IF;
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

CREATE OR REPLACE FUNCTION public.create_mass_with_assignments(p_title text, p_starts_at timestamp with time zone, p_location text, p_celebrant text, p_notes text, p_roles jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_user uuid:=auth.uid();v_mass uuid;v_count int;v_item jsonb;v_fn text;v_server uuid;v_group text;
BEGIN
 IF NOT public.has_site_permission('create_scales') THEN RAISE EXCEPTION 'Sem permissão para esta ação' USING ERRCODE='42501'; END IF;

 -- Access controlled by has_site_permission at function entry.
 IF length(trim(coalesce(p_title,''))) NOT BETWEEN 2 AND 180 OR p_starts_at IS NULL THEN
  RAISE EXCEPTION 'Informe o nome, a data e o horário da missa' USING ERRCODE='22023';
 END IF;
 -- Accept both a JSON array and the legacy double-encoded JSON string from cached iOS PWA versions.
 IF jsonb_typeof(p_roles)='string' THEN
  BEGIN p_roles := (p_roles #>> '{}')::jsonb;
  EXCEPTION WHEN others THEN RAISE EXCEPTION 'Formato de funções inválido' USING ERRCODE='22023'; END;
 END IF;
 IF jsonb_typeof(p_roles)<>'array' THEN
  RAISE EXCEPTION 'Funções inválidas' USING ERRCODE='22023';
 END IF;
 v_count:=jsonb_array_length(p_roles);
 IF v_count>80 THEN RAISE EXCEPTION 'Há funções demais nesta missa' USING ERRCODE='22023'; END IF;
 FOR v_item IN SELECT value FROM jsonb_array_elements(p_roles) LOOP
  IF jsonb_typeof(v_item)<>'object' THEN RAISE EXCEPTION 'Função inválida' USING ERRCODE='22023'; END IF;
  v_fn:=trim(coalesce(v_item->>'fn',''));
  v_group:=coalesce(nullif(v_item->>'group',''),'coroinha');
  IF v_group NOT IN ('coroinha','cerimoniario') OR NOT (
   public.can_manage_service_group(v_group)
   OR (public.has_site_permission('create_scales') AND v_group=(
     SELECT CASE WHEN p.role='cerimoniario' OR p.coordination_group='cerimoniario'
     THEN 'cerimoniario' ELSE 'coroinha' END
     FROM public.profiles p WHERE p.id=auth.uid() AND p.approved
   ))
  ) THEN RAISE EXCEPTION 'Grupo de função não autorizado' USING ERRCODE='42501'; END IF;
  IF length(v_fn) NOT BETWEEN 1 AND 120 THEN RAISE EXCEPTION 'Preencha todas as funções' USING ERRCODE='22023'; END IF;
  IF nullif(v_item->>'uid','') IS NOT NULL THEN
   BEGIN v_server:=(v_item->>'uid')::uuid;
   EXCEPTION WHEN invalid_text_representation THEN RAISE EXCEPTION 'Coroinha selecionado inválido' USING ERRCODE='22023'; END;
   IF NOT EXISTS(SELECT 1 WHERE public.is_eligible_service_member(v_server,v_group))
   THEN RAISE EXCEPTION 'O coroinha selecionado não está aprovado' USING ERRCODE='22023'; END IF;
  END IF;
 END LOOP;
 -- Uma mesma celebração (nome+horário) não pode ser publicada duas vezes por coordenações diferentes.
 PERFORM pg_advisory_xact_lock(hashtextextended(lower(trim(p_title))||'|'||p_starts_at::text,31));
 SELECT m.id INTO v_mass FROM public.masses m
 WHERE lower(trim(m.title))=lower(trim(p_title)) AND m.starts_at=p_starts_at AND m.archived_at IS NULL
 ORDER BY m.created_at ASC LIMIT 1 FOR UPDATE;
 IF v_mass IS NOT NULL THEN
  IF EXISTS(SELECT 1 FROM public.assignments WHERE mass_id=v_mass)
    OR EXISTS(SELECT 1 FROM public.masses WHERE id=v_mass AND created_by IS DISTINCT FROM v_user) THEN
   RAISE EXCEPTION 'Esta missa já foi cadastrada. Abra a escala para editar as funções do seu grupo.' USING ERRCODE='P0001';
  END IF;
  -- Corrige apenas uma criação incompleta da própria conta.
  UPDATE public.masses SET location=coalesce(p_location,''),celebrant=coalesce(p_celebrant,''),
   notes=coalesce(p_notes,''),published=true WHERE id=v_mass;
 ELSE
  INSERT INTO public.masses(title,starts_at,location,celebrant,notes,published,created_by)
  VALUES(trim(p_title),p_starts_at,coalesce(p_location,''),coalesce(p_celebrant,''),
   coalesce(p_notes,''),true,v_user) RETURNING id INTO v_mass;
 END IF;
 FOR v_item IN SELECT value FROM jsonb_array_elements(p_roles) LOOP
  v_server:=NULLIF(v_item->>'uid','')::uuid;
  INSERT INTO public.assignments(mass_id,function_name,server_id,status,service_group)
  VALUES(v_mass,trim(v_item->>'fn'),v_server,'escalado',coalesce(nullif(v_item->>'group',''),'coroinha'));
 END LOOP;
 RETURN v_mass;
END $function$;

CREATE OR REPLACE FUNCTION public.run_pending_auto_approvals()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
 s public.assignments%rowtype;
 r public.requests%rowtype;
 v_mass public.masses%rowtype;
 v_name text;
 v_count integer:=0;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.service_settings WHERE key='auto_approval_3h' AND enabled) THEN RETURN 0; END IF;
 FOR s IN
  SELECT a.* FROM public.assignments a JOIN public.masses m ON m.id=a.mass_id
  WHERE m.published AND m.starts_at>now() AND m.starts_at<=now()+INTERVAL '3 hours'
   AND (a.server_id IS NULL OR a.status='desmarcado')
  ORDER BY m.starts_at,a.id
  FOR UPDATE OF a SKIP LOCKED
 LOOP
  SELECT * INTO v_mass FROM public.masses WHERE id=s.mass_id;
  SELECT r0.* INTO r
   FROM public.requests r0 JOIN public.profiles p ON p.id=r0.user_id
   WHERE r0.mass_id=s.mass_id AND r0.status='pendente'
     AND r0.service_group=s.service_group AND public.is_eligible_service_member(p.id,s.service_group)
     AND ((r0.type='servir' AND r0.assignment_id IS NULL)
       OR (r0.type='substituir' AND r0.assignment_id=s.id AND s.status='desmarcado'))
     AND NOT EXISTS(SELECT 1 FROM public.assignments x
           WHERE x.mass_id=s.mass_id AND x.server_id=r0.user_id AND x.status<>'desmarcado')
   ORDER BY r0.created_at,r0.id LIMIT 1 FOR UPDATE OF r0 SKIP LOCKED;
  IF r.id IS NULL THEN CONTINUE; END IF;
  UPDATE public.assignments SET server_id=r.user_id,status='escalado',reason=NULL WHERE id=s.id;
  UPDATE public.requests SET status='aprovado' WHERE id=r.id;
  SELECT name INTO v_name FROM public.profiles WHERE id=r.user_id;
  INSERT INTO public.notifications(user_id,title,body,event_key)
   VALUES(r.user_id,'Você foi escalado automaticamente',
     'Você foi escalado para servir em '||to_char(v_mass.starts_at AT TIME ZONE 'America/Sao_Paulo','DD/MM/YYYY HH24:MI')||
     ', na função '||s.function_name||'.','automatic_approval');
  INSERT INTO public.notifications(user_id,title,body,event_key)
   SELECT p.id,'Aprovação automática',
     'O sistema aprovou '||coalesce(v_name,'um integrante')||' automaticamente para '||s.function_name||
     ' em '||to_char(v_mass.starts_at AT TIME ZONE 'America/Sao_Paulo','DD/MM/YYYY HH24:MI')||
     ' devido à ausência de aprovação manual.','automatic_approval'
   FROM public.profiles p WHERE p.approved AND
    (p.role='desenvolvedor' OR (p.role='coordenadora' AND p.coordination_group=s.service_group));
  v_count:=v_count+1;
  r.id:=NULL;
 END LOOP;
 RETURN v_count;
END $function$;
