CREATE OR REPLACE FUNCTION public.notify_assignment_events()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_mass public.masses%rowtype; v_name text; v_group text;
BEGIN
 IF NOT public.automation_enabled('notify_assignment_events') THEN RETURN NEW; END IF;
 SELECT * INTO v_mass FROM public.masses WHERE id=NEW.mass_id;
 IF NOT FOUND OR NOT v_mass.published THEN RETURN NEW; END IF;
 v_group:=NEW.service_group;
 SELECT coalesce(nullif(trim(name),''),'Integrante') INTO v_name FROM public.profiles WHERE id=NEW.server_id;
 IF NEW.server_id IS NOT NULL AND NEW.status NOT IN ('desmarcado','faltou')
   AND (TG_OP='INSERT' OR OLD.server_id IS DISTINCT FROM NEW.server_id OR (OLD.status='desmarcado' AND NEW.status='escalado')) THEN
  INSERT INTO public.notifications(user_id,title,body,event_key)
  SELECT p.id,'Você foi escalado(a)',
   'Você está na escala de '||v_mass.title||' em '||to_char(v_mass.starts_at AT TIME ZONE 'America/Sao_Paulo','DD/MM/YYYY "às" HH24:MI')||'.',
   CASE WHEN v_group='cerimoniario' THEN 'ceremony_assignments' ELSE 'server_assignments' END
  FROM public.profiles p WHERE p.id=NEW.server_id AND p.approved AND p.role=v_group;
  IF v_group='coroinha' THEN
   INSERT INTO public.notifications(user_id,title,body,event_key)
   SELECT l.parent_id,'Seu filho foi escalado',
   coalesce(v_name,'O coroinha')||' entrou na escala de '||v_mass.title||'.','parent_assignments'
   FROM public.parent_child_links l JOIN public.profiles p ON p.id=l.parent_id AND p.approved AND p.role='pai'
   WHERE l.child_id=NEW.server_id;
  END IF;
 END IF;
 IF TG_OP='UPDATE' AND OLD.status IS DISTINCT FROM NEW.status
 AND NEW.status IN ('confirmado','desmarcado') AND NEW.server_id IS NOT NULL THEN
  INSERT INTO public.notifications(user_id,title,body,event_key)
  SELECT p.id,CASE WHEN NEW.status='confirmado' THEN 'Escala confirmada' ELSE 'Escala desmarcada' END,
   coalesce(v_name,'Integrante')||CASE WHEN NEW.status='confirmado' THEN ' confirmou participação em ' ELSE ' desmarcou a escala de ' END||v_mass.title||'.',
   CASE WHEN p.role='desenvolvedor' THEN 'developer_system' ELSE 'coord_responses' END
  FROM public.profiles p WHERE p.approved AND
   (p.role='desenvolvedor' OR (p.role='coordenadora' AND p.coordination_group=v_group));
  IF v_group='coroinha' THEN
   INSERT INTO public.notifications(user_id,title,body,event_key)
   SELECT l.parent_id,CASE WHEN NEW.status='confirmado' THEN 'Seu filho confirmou a escala' ELSE 'Seu filho desmarcou a escala' END,
    coalesce(v_name,'O coroinha')||CASE WHEN NEW.status='confirmado' THEN ' confirmou participação em ' ELSE ' desmarcou a participação em ' END||v_mass.title||'.',
    CASE WHEN NEW.status='confirmado' THEN 'parent_confirmations' ELSE 'parent_withdrawals' END
   FROM public.parent_child_links l JOIN public.profiles p ON p.id=l.parent_id AND p.approved AND p.role='pai'
   WHERE l.child_id=NEW.server_id;
  END IF;
 END IF;
 IF NEW.server_id IS NULL AND
   (TG_OP='INSERT' OR (OLD.server_id IS NOT NULL AND NEW.server_id IS NULL)) THEN
  INSERT INTO public.notifications(user_id,title,body,event_key)
  SELECT p.id,'Vaga disponível para servir',
  'Há uma vaga de '||NEW.function_name||' na missa '||v_mass.title||' em '||
  to_char(v_mass.starts_at AT TIME ZONE 'America/Sao_Paulo','DD/MM/YYYY "às" HH24:MI')||'.',
  CASE WHEN v_group='cerimoniario' THEN 'ceremony_open_slots' ELSE 'server_open_slots' END
  FROM public.profiles p WHERE p.approved AND p.role=v_group
   AND NOT EXISTS (
     SELECT 1 FROM public.assignments a WHERE a.mass_id=NEW.mass_id
      AND a.server_id=p.id AND a.status<>'desmarcado'
   );
 END IF;
 RETURN NEW;
END $function$
;
