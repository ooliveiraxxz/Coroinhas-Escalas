-- Only the isolated migration branch. Avoid stale substitutions and approving unapproved server profiles.
DO $guard$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM migration_private.environment WHERE branch_id='br-rough-hill-bcj6lzt1') THEN RAISE EXCEPTION 'Wrong branch' USING ERRCODE='42501'; END IF;
END $guard$;
CREATE OR REPLACE FUNCTION public.approve_service_request(p_request_id uuid, p_assignment_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_request public.requests%rowtype;
 v_assignment public.assignments%rowtype;
begin
 if auth.uid() is null or not public.is_coordinator() then
   raise exception 'Somente a coordenação pode aprovar solicitações.' using errcode='42501';
 end if;
 if p_request_id is null or p_assignment_id is null then
   raise exception 'Selecione uma solicitação e uma função.';
 end if;
 select * into v_request from public.requests where id=p_request_id for update;
 if not found or v_request.status <> 'pendente' then
   raise exception 'Este pedido não está mais pendente.';
 end if;
 select * into v_assignment from public.assignments where id=p_assignment_id for update;
 if not found or v_assignment.mass_id<>v_request.mass_id then
   raise exception 'A função não pertence à missa solicitada.';
 end if;
 if not exists(select 1 from public.profiles p where p.id=v_request.user_id and p.approved and p.role='coroinha') then
   raise exception 'Solicitante sem cadastro de coroinha aprovado.' using errcode='42501';
 end if;
 if not exists(select 1 from public.masses m where m.id=v_request.mass_id and m.starts_at > now()) then
   raise exception 'Missa já iniciada; pedido não pode ser aprovado.';
 end if;
 if v_request.type='substituir' and v_assignment.status<>'desmarcado' then
   raise exception 'A vaga não está mais disponível para substituição.';
 end if;
 if v_request.type='substituir' and v_request.assignment_id is distinct from p_assignment_id then
   raise exception 'Para substituição, escolha a função indicada na solicitação.';
 end if;
 if v_request.type <> 'substituir' and v_assignment.server_id is not null and v_assignment.status<>'desmarcado' then
   raise exception 'Esta função já está ocupada. Atualize a lista de vagas.';
 end if;
 if exists(select 1 from public.assignments a where a.mass_id=v_request.mass_id and a.server_id=v_request.user_id and a.status<>'desmarcado' and a.id<>p_assignment_id) then
   raise exception 'Este coroinha já possui uma função nesta missa.';
 end if;
 update public.assignments
 set server_id=v_request.user_id,status='escalado',reason=null
 where id=v_assignment.id;
 update public.requests set status='aprovado' where id=v_request.id;
end;
$function$
;
