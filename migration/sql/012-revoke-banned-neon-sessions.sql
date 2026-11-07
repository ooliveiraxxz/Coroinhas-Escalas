-- Only the isolated branch. Ban revokes active sessions without deleting login history.
DO $guard$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM migration_private.environment WHERE branch_id='br-rough-hill-bcj6lzt1') THEN RAISE EXCEPTION 'Wrong branch' USING ERRCODE='42501'; END IF;
END $guard$;
CREATE OR REPLACE FUNCTION public.developer_manage_user(p_user uuid, p_action text, p_role text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_email text;
BEGIN
 IF NOT public.is_developer() OR auth.uid() IS NULL THEN RAISE EXCEPTION 'Acesso restrito ao desenvolvedor' USING ERRCODE='42501'; END IF;
 IF p_user=auth.uid() THEN RAISE EXCEPTION 'Não é permitido alterar sua própria conta';END IF;
 SELECT email INTO v_email FROM public.profiles WHERE id=p_user FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Usuário não encontrado';END IF;
 IF p_action='role' THEN
  IF p_role IS NULL OR p_role NOT IN ('coroinha','pai','coordenadora','desenvolvedor') THEN RAISE EXCEPTION 'Perfil inválido';END IF;
  UPDATE public.profiles SET role=p_role,approved=true WHERE id=p_user;
  UPDATE neon_auth.session SET "expiresAt"=now() WHERE "userId" IN (SELECT id FROM neon_auth."user" WHERE id::text IN (SELECT subject FROM migration_private.identity_map WHERE provider='neon' AND profile_id=p_user)) AND "expiresAt">now();
  RETURN 'Perfil atualizado';
 ELSIF p_action='ban' THEN
  INSERT INTO public.banned_emails(email,banned_by) VALUES(lower(v_email),auth.uid()) ON CONFLICT DO NOTHING;
  UPDATE neon_auth."user" SET banned=true WHERE id::text IN(SELECT subject FROM migration_private.identity_map WHERE provider='neon' AND profile_id=p_user);
  -- Expire all active Neon sessions of the blocked identity without deleting history.
  UPDATE neon_auth.session
  SET "expiresAt"=now(), "updatedAt"=now()
  WHERE "userId" IN (
    SELECT id FROM neon_auth."user" WHERE id::text IN (
      SELECT subject FROM migration_private.identity_map WHERE provider='neon' AND profile_id=p_user
    )
  ) AND "expiresAt">now();
  UPDATE public.profiles SET approved=false WHERE id=p_user;
  UPDATE neon_auth.session SET "expiresAt"=now() WHERE "userId" IN (SELECT id FROM neon_auth."user" WHERE id::text IN (SELECT subject FROM migration_private.identity_map WHERE provider='neon' AND profile_id=p_user)) AND "expiresAt">now();
  RETURN 'Conta bloqueada';
 ELSIF p_action='delete' THEN
  RAISE EXCEPTION 'Exclusão desativada durante a migração: nenhum registro será apagado';
 ELSE RAISE EXCEPTION 'Ação inválida';END IF;
END $function$
;
