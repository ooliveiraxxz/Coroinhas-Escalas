-- Preserve explicit user permissions; allow ceremonial members to vote by default.
CREATE OR REPLACE FUNCTION public.respond_assignment(p_id uuid, p_action text, p_reason text DEFAULT ''::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v public.assignments%rowtype;
 t timestamptz;
begin
 IF p_action='confirmar' AND NOT public.has_site_permission('confirm_assignment') THEN RAISE EXCEPTION 'Sem permissão para confirmar escala' USING ERRCODE='42501'; END IF;
 IF p_action='desmarcar' AND NOT public.has_site_permission('unassign_self') THEN RAISE EXCEPTION 'Sem permissão para desmarcar escala' USING ERRCODE='42501'; END IF;

 if auth.uid() is null or not public.is_approved() then
  raise exception 'Cadastro aguardando aprovação';
 end if;
 select * into v from public.assignments
 where id=p_id and server_id=auth.uid() for update;
 if not found then
  raise exception 'Escala não encontrada para sua conta';
 end if;
 select starts_at into t from public.masses where id=v.mass_id;
 if t is null then raise exception 'Missa não encontrada'; end if;
 if p_action='desmarcar' then
  if length(trim(coalesce(p_reason,'')))<3 then
   raise exception 'Informe uma justificativa com pelo menos 3 caracteres';
  end if;
  if v.status in ('desmarcado','faltou','presente') then
   raise exception 'Esta escala não permite desistência';
  end if;
  update public.assignments set status='desmarcado',reason=trim(p_reason) where id=p_id;
  if t>now() AND public.automation_enabled('notify_assignment_events') then
    insert into public.notifications(user_id,title,body,event_key)
    select id,'Vaga para substituição','Função: '||v.function_name||' • '||
       to_char(t at time zone 'America/Sao_Paulo','DD/MM/YYYY HH24:MI'), CASE WHEN role='coordenadora' THEN 'coord_responses' WHEN role='desenvolvedor' THEN 'general' ELSE 'server_substitutes' END
    from public.profiles where approved=true and id<>auth.uid() AND
     (role=v.service_group OR role='desenvolvedor' OR (role='coordenadora' AND coordination_group=v.service_group));
  end if;
 elsif p_action='confirmar' then
  if (t AT TIME ZONE 'America/Sao_Paulo')::date <> (now() AT TIME ZONE 'America/Sao_Paulo')::date
     OR t<=now() then
    raise exception 'Confirmação disponível somente no dia da missa, antes de começar';
  end if;
  if v.status not in ('escalado','confirmado') then
   raise exception 'Esta escala não pode ser confirmada';
  end if;
  update public.assignments set status='confirmado' where id=p_id;
 else
  raise exception 'Ação inválida';
 end if;
end;
$function$
;
UPDATE public.permission_catalog SET default_roles=array_append(default_roles,'cerimoniario') WHERE key='vote_polls' AND NOT ('cerimoniario'=ANY(default_roles));
