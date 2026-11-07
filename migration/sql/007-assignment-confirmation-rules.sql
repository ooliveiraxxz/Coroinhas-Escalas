-- Executar SOMENTE em migration-coroinhas-20261106.
-- Confirmar apenas no dia da missa (horário de São Paulo, antes do início).
-- Desmarcar qualquer dia enquanto status for escalado/confirmado, com justificativa.
-- Não enviar notificações de substituição de missas já iniciadas.
DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM migration_private.environment WHERE branch_id='br-rough-hill-bcj6lzt1') THEN RAISE EXCEPTION 'Branch incorreta'; END IF; END $$;
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
  if t>now() then
    insert into public.notifications(user_id,title,body)
    select id,'Vaga para substituição','Função: '||v.function_name||' • '||
       to_char(t at time zone 'America/Sao_Paulo','DD/MM/YYYY HH24:MI')
    from public.profiles where approved=true and role IN ('coroinha','coordenadora','desenvolvedor') and id<>auth.uid();
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
