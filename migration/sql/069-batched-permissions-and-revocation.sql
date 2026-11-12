-- Batch tracking keeps individual audit evidence while grouping one user command.
ALTER TABLE public.permission_rules ADD COLUMN IF NOT EXISTS batch_id uuid;

CREATE OR REPLACE FUNCTION public.developer_apply_permissions(p_user uuid,p_changes jsonb,p_until timestamptz,p_confirmation text)
 RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $fn$
DECLARE x jsonb;v_count integer:=0;v_batch uuid:=gen_random_uuid();
BEGIN
 IF NOT public.is_developer() OR trim(coalesce(p_confirmation,''))<>'DESENVOLVEDOR' THEN RAISE EXCEPTION 'Confirmação de desenvolvedor inválida' USING ERRCODE='42501'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.profiles WHERE id=p_user AND role<>'desenvolvedor') THEN RAISE EXCEPTION 'Conta protegida' USING ERRCODE='42501'; END IF;
 IF jsonb_typeof(p_changes)<>'array' OR jsonb_array_length(p_changes) NOT BETWEEN 1 AND 50 THEN RAISE EXCEPTION 'Alterações inválidas' USING ERRCODE='22023'; END IF;
 IF p_until IS NOT NULL AND (p_until<=now() OR p_until>now()+interval '365 days') THEN RAISE EXCEPTION 'Prazo inválido' USING ERRCODE='22023'; END IF;
 IF (SELECT count(DISTINCT item.value->>'key') FROM jsonb_array_elements(p_changes) AS item(value))<>jsonb_array_length(p_changes) THEN RAISE EXCEPTION 'Permissão repetida na mesma operação' USING ERRCODE='22023'; END IF;
 FOR x IN SELECT value FROM jsonb_array_elements(p_changes) LOOP
  IF jsonb_typeof(x)<>'object' OR jsonb_typeof(x->'allowed')<>'boolean' OR NOT EXISTS(SELECT 1 FROM public.permission_catalog WHERE key=x->>'key') THEN RAISE EXCEPTION 'Função desconhecida' USING ERRCODE='22023'; END IF;
  INSERT INTO public.permission_rules(subject_user,permission_key,allowed,expires_at,created_by,batch_id)
  VALUES(p_user,x->>'key',(x->>'allowed')::boolean,p_until,auth.uid(),v_batch);
  v_count:=v_count+1;
 END LOOP;
 RETURN v_count;
END $fn$;

CREATE OR REPLACE FUNCTION public.developer_revoke_permissions_bulk(p_user uuid,p_ids uuid[],p_confirmation text)
 RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $fn$
DECLARE v_batch uuid:=gen_random_uuid();v_count integer;v_keys text[];
BEGIN
 IF NOT public.is_developer() OR trim(coalesce(p_confirmation,''))<>'DESENVOLVEDOR' THEN RAISE EXCEPTION 'Confirmação inválida' USING ERRCODE='42501'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.profiles WHERE id=p_user AND role<>'desenvolvedor') THEN RAISE EXCEPTION 'Conta protegida' USING ERRCODE='42501'; END IF;
 IF p_ids IS NULL OR cardinality(p_ids) NOT BETWEEN 1 AND 100 OR cardinality(p_ids)<>(SELECT count(DISTINCT v) FROM unnest(p_ids) v) THEN RAISE EXCEPTION 'Seleção inválida' USING ERRCODE='22023'; END IF;
 SELECT array_agg(DISTINCT r.permission_key) INTO v_keys FROM public.permission_rules r
 WHERE r.id=ANY(p_ids) AND r.subject_user=p_user AND r.expires_at>now();
 IF (SELECT count(*) FROM public.permission_rules r WHERE r.id=ANY(p_ids) AND r.subject_user=p_user AND r.expires_at>now())<>cardinality(p_ids) THEN RAISE EXCEPTION 'Uma permissão selecionada já expirou ou não pertence a este usuário' USING ERRCODE='22023'; END IF;
 UPDATE public.permission_rules
 SET expires_at=now(),batch_id=v_batch
 WHERE subject_user=p_user AND permission_key=ANY(v_keys) AND expires_at>now();
 GET DIAGNOSTICS v_count=ROW_COUNT;
 RETURN v_count;
END $fn$;

REVOKE ALL ON FUNCTION public.developer_revoke_permissions_bulk(uuid,uuid[],text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.developer_revoke_permissions_bulk(uuid,uuid[],text) TO coroinhas_app;
