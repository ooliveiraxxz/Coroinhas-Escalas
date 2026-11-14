-- 084: Escolha de tema exige permissão; todos os perfis começam bloqueados por padrão.
INSERT INTO public.permission_catalog(key,category,label,default_roles,sensitive)
VALUES('choose_theme','Desenvolvedor','Escolher tema visual do aplicativo',ARRAY[]::text[],false)
ON CONFLICT(key) DO UPDATE SET category=excluded.category,label=excluded.label,default_roles=excluded.default_roles,sensitive=excluded.sensitive;

ALTER TABLE public.profiles ALTER COLUMN theme_preference DROP NOT NULL;
ALTER TABLE public.profiles ALTER COLUMN theme_preference DROP DEFAULT;
-- Os perfis não desenvolvedores não possuíam seletor antes desta migração;
-- remove a preferência coroinha preenchida pelo default anterior.
UPDATE public.profiles SET theme_preference=NULL WHERE role<>'desenvolvedor' AND theme_preference='coroinha';

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
 IF p.role='desenvolvedor' THEN RETURN true; END IF;
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
END $function$

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
  (p.role='desenvolvedor' AND c.key<>'choose_theme') OR p.role=ANY(c.default_roles) OR (p.role='coordenadora' AND ('coordenadora_'||coalesce(p.coordination_group,'coroinha'))=ANY(c.default_roles))),
  'default',(p.role='desenvolvedor' AND c.key<>'choose_theme') OR p.role=ANY(c.default_roles) OR (p.role='coordenadora' AND ('coordenadora_'||coalesce(p.coordination_group,'coroinha'))=ANY(c.default_roles)),
  'sensitive',c.sensitive) ORDER BY c.category,c.label) FROM public.permission_catalog c),'[]'::jsonb);
END $function$

CREATE OR REPLACE FUNCTION public.developer_apply_permissions(p_user uuid, p_changes jsonb, p_until timestamp with time zone, p_confirmation text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE x jsonb;v_count integer:=0;v_batch uuid:=gen_random_uuid();
BEGIN
 IF NOT public.is_developer() OR trim(coalesce(p_confirmation,''))<>'DESENVOLVEDOR' THEN RAISE EXCEPTION 'Confirmação de desenvolvedor inválida' USING ERRCODE='42501'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.profiles WHERE id=p_user) THEN RAISE EXCEPTION 'Conta não encontrada' USING ERRCODE='42501'; END IF;
 IF jsonb_typeof(p_changes)<>'array' OR jsonb_array_length(p_changes) NOT BETWEEN 1 AND 50 THEN RAISE EXCEPTION 'Alterações inválidas' USING ERRCODE='22023'; END IF;
 IF p_until IS NOT NULL AND (p_until<=now() OR p_until>now()+interval '365 days') THEN RAISE EXCEPTION 'Prazo inválido' USING ERRCODE='22023'; END IF;
 IF (SELECT count(DISTINCT item.value->>'key') FROM jsonb_array_elements(p_changes) AS item(value))<>jsonb_array_length(p_changes) THEN RAISE EXCEPTION 'Permissão repetida na mesma operação' USING ERRCODE='22023'; END IF;
 FOR x IN SELECT value FROM jsonb_array_elements(p_changes) LOOP
  IF jsonb_typeof(x)<>'object' OR jsonb_typeof(x->'allowed')<>'boolean' OR NOT EXISTS(SELECT 1 FROM public.permission_catalog WHERE key=x->>'key') THEN RAISE EXCEPTION 'Função desconhecida' USING ERRCODE='22023'; END IF;
  IF EXISTS(SELECT 1 FROM public.profiles WHERE id=p_user AND role='desenvolvedor') AND x->>'key'<>'choose_theme' THEN RAISE EXCEPTION 'Conta de Desenvolvedor protegida para outras permissões' USING ERRCODE='42501'; END IF;
  INSERT INTO public.permission_rules(subject_user,permission_key,allowed,expires_at,created_by,batch_id)
  VALUES(p_user,x->>'key',(x->>'allowed')::boolean,p_until,auth.uid(),v_batch);
  v_count:=v_count+1;
 END LOOP;
 RETURN v_count;
END $function$

CREATE OR REPLACE FUNCTION public.set_my_theme(p_theme text)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_id uuid:=auth.uid();
BEGIN
 IF v_id IS NULL OR NOT public.has_site_permission('choose_theme') THEN
  RAISE EXCEPTION 'Você não tem permissão para escolher o tema' USING ERRCODE='42501';
 END IF;
 IF p_theme IS NULL OR p_theme NOT IN ('coroinha','cerimoniario') THEN
  RAISE EXCEPTION 'Tema inválido' USING ERRCODE='22023';
 END IF;
 UPDATE public.profiles SET theme_preference=p_theme WHERE id=v_id AND approved;
 IF NOT FOUND THEN RAISE EXCEPTION 'Conta não encontrada' USING ERRCODE='42501'; END IF;
 RETURN p_theme;
END;
$function$;
REVOKE ALL ON FUNCTION public.set_my_theme(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_my_theme(text) TO coroinhas_app;
REVOKE ALL ON FUNCTION public.developer_set_my_theme(text) FROM PUBLIC,coroinhas_app,coroinhas_gateway;
