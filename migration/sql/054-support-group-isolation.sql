-- Apply first to isolated homologation; preserve existing tickets and accounts.
CREATE OR REPLACE FUNCTION public.can_manage_support_request(p_requester uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $function$
 SELECT public.is_developer() OR (
  EXISTS(SELECT 1 FROM public.profiles WHERE id=auth.uid() AND approved AND role='coordenadora')
  AND public.can_manage_service_group((SELECT CASE WHEN role='cerimoniario' THEN 'cerimoniario' ELSE 'coroinha' END FROM public.profiles WHERE id=p_requester))
 );
$function$;
REVOKE ALL ON FUNCTION public.can_manage_support_request(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.can_manage_support_request(uuid) TO coroinhas_app;


CREATE OR REPLACE FUNCTION public.support_coord_create(p_category text, p_message text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_user uuid:=auth.uid();v_id uuid;v_protocol text;v_text text:=trim(coalesce(p_message,''));v_category text:=trim(coalesce(p_category,''));
BEGIN
 IF v_user IS NULL OR NOT public.is_approved() THEN RAISE EXCEPTION 'Acesso não autorizado' USING ERRCODE='42501'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.profiles WHERE id=v_user AND role IN ('coroinha','cerimoniario','pai','desenvolvedor')) THEN
  RAISE EXCEPTION 'Seu perfil não pode iniciar este atendimento' USING ERRCODE='42501'; END IF;
 IF v_category NOT IN ('Dúvida','Problema na escala','Sugestão','Outro') THEN RAISE EXCEPTION 'Escolha o assunto do atendimento' USING ERRCODE='22023'; END IF;
 IF length(v_text) NOT BETWEEN 1 AND 2000 THEN RAISE EXCEPTION 'Escreva uma mensagem de até 2000 caracteres' USING ERRCODE='22023'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(v_user::text,19));
 IF EXISTS(SELECT 1 FROM public.support_tickets WHERE requester_id=v_user AND status='aberto' AND target_role='coordenadora') THEN
  RAISE EXCEPTION 'Você já possui um chat aberto com a coordenação' USING ERRCODE='P0001'; END IF;
 v_protocol:='COO-'||to_char(now() AT TIME ZONE 'America/Sao_Paulo','YYYY')||'-'||lpad(nextval('public.support_ticket_number_seq'::regclass)::text,6,'0');
 INSERT INTO public.support_tickets(protocol,requester_id,category,target_role)
 VALUES(v_protocol,v_user,v_category,'coordenadora') RETURNING id INTO v_id;
 INSERT INTO public.support_chat_messages(ticket_id,sender_id,body) VALUES(v_id,v_user,v_text);
 INSERT INTO public.notifications(user_id,title,body,event_key)
 SELECT id,'Novo chat com a coordenação','Protocolo '||v_protocol||' · '||v_category,'coord_support'
 FROM public.profiles WHERE approved AND role='coordenadora'
 AND coordination_group=(SELECT CASE WHEN role='cerimoniario' THEN 'cerimoniario' ELSE 'coroinha' END FROM public.profiles WHERE id=v_user);
 RETURN jsonb_build_object('id',v_id,'protocol',v_protocol);
END $function$
;

CREATE OR REPLACE FUNCTION public.support_coord_list()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_user uuid:=auth.uid();v_manager boolean;
BEGIN
 IF v_user IS NULL OR NOT public.is_approved() THEN RAISE EXCEPTION 'Acesso não autorizado' USING ERRCODE='42501'; END IF;
 SELECT EXISTS(SELECT 1 FROM public.profiles WHERE id=v_user AND approved AND role='coordenadora') INTO v_manager;
 RETURN coalesce((
  SELECT jsonb_agg(jsonb_build_object(
   'id',t.id,'protocol',t.protocol,'category',t.category,'status',t.status,
   'requester_name',p.name,'requester_email',p.email,
   'created_at',t.created_at,'updated_at',t.updated_at,'closed_at',t.closed_at,
   'message_count',(SELECT count(*) FROM public.support_chat_messages m WHERE m.ticket_id=t.id),
   'last_message',(SELECT left(m.body,140) FROM public.support_chat_messages m WHERE m.ticket_id=t.id ORDER BY m.created_at DESC,m.id DESC LIMIT 1)
  ) ORDER BY (t.status='aberto') DESC,t.updated_at DESC)
  FROM public.support_tickets t JOIN public.profiles p ON p.id=t.requester_id
  WHERE t.archived_at IS NULL AND t.target_role='coordenadora'
    AND ((v_manager AND public.can_manage_support_request(t.requester_id)) OR (t.requester_id=v_user AND t.status='aberto'))
 ),'[]'::jsonb);
END $function$
;

CREATE OR REPLACE FUNCTION public.support_coord_messages(p_ticket uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_user uuid:=auth.uid();v_manager boolean;v_ticket public.support_tickets%ROWTYPE;
BEGIN
 IF v_user IS NULL OR NOT public.is_approved() THEN RAISE EXCEPTION 'Acesso não autorizado' USING ERRCODE='42501'; END IF;
 SELECT EXISTS(SELECT 1 FROM public.profiles WHERE id=v_user AND approved AND role='coordenadora') INTO v_manager;
 SELECT * INTO v_ticket FROM public.support_tickets WHERE id=p_ticket;
 IF NOT FOUND OR v_ticket.archived_at IS NOT NULL OR v_ticket.target_role<>'coordenadora' OR ((NOT v_manager OR NOT public.can_manage_support_request(v_ticket.requester_id)) AND (v_ticket.requester_id<>v_user OR v_ticket.status<>'aberto')) THEN
  RAISE EXCEPTION 'Atendimento não encontrado' USING ERRCODE='42501'; END IF;
 RETURN coalesce((
  SELECT jsonb_agg(jsonb_build_object(
   'id',m.id,'body',m.body,'sender_id',m.sender_id,
   'sender_name',coalesce(p.name,'Usuário'),'developer',p.role='coordenadora',
   'created_at',m.created_at
  ) ORDER BY m.created_at,m.id)
  FROM public.support_chat_messages m JOIN public.profiles p ON p.id=m.sender_id
  WHERE m.ticket_id=p_ticket
 ),'[]'::jsonb);
END $function$
;

CREATE OR REPLACE FUNCTION public.support_coord_send(p_ticket uuid, p_message text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_user uuid:=auth.uid();v_ticket public.support_tickets%ROWTYPE;v_text text:=trim(coalesce(p_message,''));v_manager boolean;
BEGIN
 IF v_user IS NULL OR NOT public.is_approved() THEN RAISE EXCEPTION 'Acesso não autorizado' USING ERRCODE='42501'; END IF;
 IF length(v_text) NOT BETWEEN 1 AND 2000 THEN RAISE EXCEPTION 'Escreva uma mensagem de até 2000 caracteres' USING ERRCODE='22023'; END IF;
 SELECT EXISTS(SELECT 1 FROM public.profiles WHERE id=v_user AND approved AND role='coordenadora') INTO v_manager;
 SELECT * INTO v_ticket FROM public.support_tickets WHERE id=p_ticket FOR UPDATE;
 IF NOT FOUND OR v_ticket.target_role<>'coordenadora' OR ((NOT v_manager OR NOT public.can_manage_support_request(v_ticket.requester_id)) AND v_ticket.requester_id<>v_user) THEN
  RAISE EXCEPTION 'Atendimento não encontrado' USING ERRCODE='42501'; END IF;
 IF v_ticket.status<>'aberto' THEN RAISE EXCEPTION 'Este atendimento foi encerrado' USING ERRCODE='22023'; END IF;
 INSERT INTO public.support_chat_messages(ticket_id,sender_id,body) VALUES(p_ticket,v_user,v_text);
 UPDATE public.support_tickets SET updated_at=now() WHERE id=p_ticket;
 IF v_manager THEN
  INSERT INTO public.notifications(user_id,title,body,event_key)
  VALUES(v_ticket.requester_id,'Resposta da coordenação','Há uma nova mensagem no protocolo '||v_ticket.protocol||'.','support_replies');
 ELSE
  INSERT INTO public.notifications(user_id,title,body,event_key)
  SELECT id,'Nova mensagem de integrante','O solicitante respondeu ao protocolo '||v_ticket.protocol||'.','coord_support'
  FROM public.profiles WHERE approved AND role='coordenadora'
 AND coordination_group=(SELECT CASE WHEN role='cerimoniario' THEN 'cerimoniario' ELSE 'coroinha' END FROM public.profiles WHERE id=v_user);
 END IF;
 RETURN jsonb_build_object('sent',true,'protocol',v_ticket.protocol);
END $function$
;

CREATE OR REPLACE FUNCTION public.support_coord_close(p_ticket uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_ticket public.support_tickets%ROWTYPE;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.profiles WHERE id=auth.uid() AND approved AND role='coordenadora')
 THEN RAISE EXCEPTION 'Somente a coordenação pode encerrar o atendimento' USING ERRCODE='42501'; END IF;
 SELECT * INTO v_ticket FROM public.support_tickets WHERE id=p_ticket AND target_role='coordenadora' FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Atendimento não encontrado' USING ERRCODE='22023'; END IF;
 IF NOT public.can_manage_support_request(v_ticket.requester_id) THEN RAISE EXCEPTION 'Atendimento de outro grupo' USING ERRCODE='42501'; END IF;
 IF v_ticket.status='encerrado' THEN RETURN jsonb_build_object('closed',true,'protocol',v_ticket.protocol); END IF;
 UPDATE public.support_tickets SET status='encerrado',closed_at=now(),closed_by=auth.uid(),updated_at=now() WHERE id=p_ticket;
 INSERT INTO public.notifications(user_id,title,body,event_key)
 VALUES(v_ticket.requester_id,'Conversa encerrada','Sua conversa com a coordenação, protocolo '||v_ticket.protocol||', foi encerrada.','support_replies');
 RETURN jsonb_build_object('closed',true,'protocol',v_ticket.protocol);
END $function$
;