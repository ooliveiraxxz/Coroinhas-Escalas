-- Developer may turn own UI permissions off; role-based recovery through Permissões remains.
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
  IF EXISTS(SELECT 1 FROM public.profiles WHERE id=p_user AND role='desenvolvedor')
     AND p_user<>auth.uid() AND x->>'key'<>'choose_theme' THEN
   RAISE EXCEPTION 'As permissões administrativas só podem ser ajustadas pelo próprio Desenvolvedor' USING ERRCODE='42501';
  END IF;
  INSERT INTO public.permission_rules(subject_user,permission_key,allowed,expires_at,created_by,batch_id)
  VALUES(p_user,x->>'key',(x->>'allowed')::boolean,p_until,auth.uid(),v_batch);
  v_count:=v_count+1;
 END LOOP;
 RETURN v_count;
END $function$
