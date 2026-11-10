-- Gestão de contas: apagar permite recadastro; banir impede recadastro no Neon Auth.
-- Exclusivamente Desenvolvedor para exclusão/banimento, com proteção contra autoexclusão.
-- Mantém auditoria e escalas existentes; limpa sessões, dados vinculados e credenciais da conta.
-- A função de cadastro bloqueia e-mails banidos mesmo após exclusão da identidade.

CREATE OR REPLACE FUNCTION migration_private.block_banned_auth_signup()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
 IF NEW.email IS NULL OR btrim(NEW.email)='' THEN
  RAISE EXCEPTION 'E-mail obrigatório' USING ERRCODE='23514';
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(lower(btrim(NEW.email)),8271));
 IF EXISTS(SELECT 1 FROM public.banned_emails WHERE email=lower(btrim(NEW.email))) THEN
  RAISE EXCEPTION 'Este e-mail está impedido de criar uma conta' USING ERRCODE='42501';
 END IF;
 RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION migration_private.remove_site_account(p_user uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_auth_id uuid;
BEGIN
 SELECT subject::uuid INTO v_auth_id FROM migration_private.identity_map
 WHERE provider='neon' AND profile_id=p_user;
 IF v_auth_id IS NULL OR NOT EXISTS(SELECT 1 FROM neon_auth."user" WHERE id=v_auth_id)
 THEN RAISE EXCEPTION 'Conta do Neon Auth não localizada. Nenhuma exclusão efetuada.' USING ERRCODE='P0001'; END IF;
 DELETE FROM public.push_subscriptions WHERE user_id=p_user;
 UPDATE public.assignments SET server_id=NULL,status='escalado',reason=NULL WHERE server_id=p_user;
 UPDATE public.masses SET created_by=NULL WHERE created_by=p_user;
 DELETE FROM public.poll_votes WHERE user_id=p_user;
 DELETE FROM public.polls WHERE created_by=p_user;
 DELETE FROM public.screen_announcements WHERE created_by=p_user;
 DELETE FROM public.messages WHERE user_id=p_user;
 DELETE FROM public.support_tickets WHERE requester_id=p_user;
 DELETE FROM public.support_chat_messages WHERE sender_id=p_user;
 UPDATE public.support_tickets SET closed_by=NULL WHERE closed_by=p_user;
 UPDATE public.permission_rules SET created_by=NULL WHERE created_by=p_user;
 DELETE FROM migration_private.identity_map WHERE provider='neon' AND profile_id=p_user;
 DELETE FROM neon_auth."user" WHERE id=v_auth_id;
 DELETE FROM public.profiles WHERE id=p_user;
END $function$;

CREATE OR REPLACE FUNCTION public.developer_manage_user(p_user uuid, p_action text, p_role text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_email text;v_role text;
BEGIN
 IF auth.uid() IS NULL OR NOT public.has_site_permission('manage_users') THEN
  RAISE EXCEPTION 'Acesso restrito' USING ERRCODE='42501';
 END IF;
 IF p_user=auth.uid() THEN RAISE EXCEPTION 'Não é permitido alterar sua própria conta' USING ERRCODE='42501'; END IF;
 SELECT lower(btrim(email)),role INTO v_email,v_role FROM public.profiles WHERE id=p_user FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Usuário não encontrado' USING ERRCODE='P0001'; END IF;
 IF p_action='role' THEN
  IF NOT public.is_developer() AND (v_role='desenvolvedor' OR p_role='desenvolvedor') THEN
   RAISE EXCEPTION 'Conta de desenvolvedor protegida' USING ERRCODE='42501'; END IF;
  IF p_role IS NULL OR p_role NOT IN ('coroinha','cerimoniario','pai','coordenadora','coordenadora_cerimoniario','desenvolvedor') THEN
   RAISE EXCEPTION 'Perfil inválido' USING ERRCODE='22023'; END IF;
  UPDATE public.profiles SET role=CASE WHEN p_role='coordenadora_cerimoniario' THEN 'coordenadora' ELSE p_role END,
   coordination_group=CASE WHEN p_role IN ('cerimoniario','coordenadora_cerimoniario') THEN 'cerimoniario' ELSE 'coroinha' END,
   approved=true WHERE id=p_user;
  UPDATE neon_auth.session SET "expiresAt"=now(),"updatedAt"=now()
   WHERE "userId" IN (SELECT subject::uuid FROM migration_private.identity_map WHERE provider='neon' AND profile_id=p_user)
    AND "expiresAt">now();
  RETURN 'Perfil atualizado';
 ELSIF p_action IN ('delete','ban') THEN
  IF NOT public.is_developer() THEN RAISE EXCEPTION 'Somente o Desenvolvedor pode excluir ou banir contas' USING ERRCODE='42501'; END IF;
  IF v_role='desenvolvedor' THEN RAISE EXCEPTION 'Conta de Desenvolvedor protegida' USING ERRCODE='42501'; END IF;
  IF p_action='ban' THEN
   PERFORM pg_advisory_xact_lock(hashtextextended(v_email,8271));
   INSERT INTO public.banned_emails(email,banned_by) VALUES(v_email,auth.uid()) ON CONFLICT (email) DO NOTHING;
  END IF;
  PERFORM migration_private.remove_site_account(p_user);
  RETURN CASE WHEN p_action='ban' THEN 'E-mail banido e conta excluída' ELSE 'Conta excluída; novo cadastro permitido' END;
 ELSE RAISE EXCEPTION 'Ação inválida' USING ERRCODE='22023'; END IF;
END $function$;

DROP TRIGGER IF EXISTS prevent_banned_neon_signup ON neon_auth."user";
CREATE TRIGGER prevent_banned_neon_signup BEFORE INSERT ON neon_auth."user" FOR EACH ROW EXECUTE FUNCTION migration_private.block_banned_auth_signup();
REVOKE ALL ON FUNCTION migration_private.block_banned_auth_signup(),migration_private.remove_site_account(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.developer_manage_user(uuid,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.developer_manage_user(uuid,text,text) TO coroinhas_app;
