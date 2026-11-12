-- Compatibility for older installed PWA clients: accept JSON arrays or double-encoded JSON text.
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
   IF NOT EXISTS(SELECT 1 FROM public.profiles WHERE id=v_server AND approved AND role=v_group)
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
END $function$
;
