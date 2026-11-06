CREATE FUNCTION public.developer_manage_user(p_user uuid,p_action text,p_role text DEFAULT NULL)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_email text;
BEGIN
 IF NOT public.is_developer() OR auth.uid() IS NULL THEN RAISE EXCEPTION 'Acesso restrito ao desenvolvedor' USING ERRCODE='42501'; END IF;
 IF p_user=auth.uid() THEN RAISE EXCEPTION 'Não é permitido alterar sua própria conta';END IF;
 SELECT email INTO v_email FROM public.profiles WHERE id=p_user FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Usuário não encontrado';END IF;
 IF p_action='role' THEN
  IF p_role IS NULL OR p_role NOT IN ('coroinha','pai','coordenadora','desenvolvedor') THEN RAISE EXCEPTION 'Perfil inválido';END IF;
  UPDATE public.profiles SET role=p_role,approved=true WHERE id=p_user;
  RETURN 'Perfil atualizado';
 ELSIF p_action='ban' THEN
  INSERT INTO public.banned_emails(email,banned_by) VALUES(lower(v_email),auth.uid()) ON CONFLICT DO NOTHING;
  UPDATE neon_auth."user" SET banned=true WHERE id::text IN(SELECT subject FROM migration_private.identity_map WHERE provider='neon' AND profile_id=p_user);
  UPDATE public.profiles SET approved=false WHERE id=p_user;
  RETURN 'Conta bloqueada';
 ELSIF p_action='delete' THEN
  RAISE EXCEPTION 'Exclusão desativada durante a migração: nenhum registro será apagado';
 ELSE RAISE EXCEPTION 'Ação inválida';END IF;
END $$;
REVOKE ALL ON FUNCTION public.developer_manage_user(uuid,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.developer_manage_user(uuid,text,text) TO coroinhas_app;
CREATE VIEW public.profile_directory WITH(security_invoker=true) AS
SELECT id,name,CASE WHEN id=auth.uid() OR public.is_coordinator() THEN email END AS email,role,approved,
photo_url,CASE WHEN public.is_coordinator() THEN notes END AS notes,created_at,
CASE WHEN id=auth.uid() OR public.is_coordinator() THEN notification_preferences END AS notification_preferences,
CASE WHEN id=auth.uid() OR public.is_coordinator() THEN last_seen_at END AS last_seen_at FROM public.profiles;
GRANT SELECT ON public.profile_directory TO coroinhas_app;
