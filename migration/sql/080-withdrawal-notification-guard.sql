-- QA 080: avoid announcing a free replacement slot after synchronous auto-refill.
-- Only apply to isolated homologation, never production without approval.
CREATE OR REPLACE FUNCTION public.respond_assignment(p_id uuid, p_action text, p_reason text DEFAULT ''::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v public.assignments%rowtype; t timestamptz;
BEGIN
 IF p_action='confirmar' AND NOT public.has_site_permission('confirm_assignment') THEN RAISE EXCEPTION 'Sem permissão para confirmar escala' USING ERRCODE='42501'; END IF;
 IF p_action='desmarcar' AND NOT public.has_site_permission('unassign_self') THEN RAISE EXCEPTION 'Sem permissão para desmarcar escala' USING ERRCODE='42501'; END IF;
 IF auth.uid() IS NULL OR NOT public.is_approved() THEN RAISE EXCEPTION 'Cadastro aguardando aprovação'; END IF;
 SELECT * INTO v FROM public.assignments WHERE id=p_id AND server_id=auth.uid() FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Escala não encontrada para sua conta'; END IF;
 SELECT starts_at INTO t FROM public.masses WHERE id=v.mass_id;
 IF t IS NULL THEN RAISE EXCEPTION 'Missa não encontrada'; END IF;
 IF p_action='desmarcar' THEN
  IF length(trim(coalesce(p_reason,'')))<3 THEN RAISE EXCEPTION 'Informe uma justificativa com pelo menos 3 caracteres'; END IF;
  IF v.status IN ('desmarcado','faltou','presente') THEN RAISE EXCEPTION 'Esta escala não permite desistência'; END IF;
  UPDATE public.assignments SET status='desmarcado',reason=trim(p_reason) WHERE id=p_id;
  IF t>now() AND EXISTS(SELECT 1 FROM public.assignments x WHERE x.id=p_id AND x.status='desmarcado') THEN
   INSERT INTO public.notifications(user_id,title,body,event_key)
   SELECT p.id,'Vaga para substituição','Função: '||v.function_name||' • '||
    to_char(t AT TIME ZONE 'America/Sao_Paulo','DD/MM/YYYY HH24:MI'),
    CASE WHEN p.role='desenvolvedor' THEN 'developer_system'
         WHEN p.role='coordenadora' THEN 'coord_responses'
         WHEN v.service_group='cerimoniario' THEN 'ceremony_substitutes' ELSE 'server_substitutes' END
   FROM public.profiles p WHERE p.approved AND p.id<>auth.uid() AND
    (p.role='desenvolvedor' OR
     (p.role='coordenadora' AND p.coordination_group=v.service_group) OR
     p.role=v.service_group);
  END IF;
 ELSIF p_action='confirmar' THEN
  IF (t AT TIME ZONE 'America/Sao_Paulo')::date<>(now() AT TIME ZONE 'America/Sao_Paulo')::date OR t<=now() THEN
   RAISE EXCEPTION 'Confirmação disponível somente no dia da missa, antes de começar'; END IF;
  IF v.status NOT IN ('escalado','confirmado') THEN RAISE EXCEPTION 'Esta escala não pode ser confirmada'; END IF;
  UPDATE public.assignments SET status='confirmado' WHERE id=p_id;
 ELSE RAISE EXCEPTION 'Ação inválida';
 END IF;
END $function$
