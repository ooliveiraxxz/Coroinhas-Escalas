-- A user granted manage_users can change roles through developer_manage_user,
-- but cannot directly update profile roles through the profile UPDATE endpoint.
-- The target-specific transaction-local guard is set only by the validated RPC.
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
  -- Allow only this validated administrative call to change the target role.
  PERFORM set_config('app.delegated_role_change_target',p_user::text,true);
  UPDATE public.profiles SET role=CASE WHEN p_role='coordenadora_cerimoniario' THEN 'coordenadora' ELSE p_role END,
   coordination_group=CASE WHEN p_role IN ('cerimoniario','coordenadora_cerimoniario') THEN 'cerimoniario' ELSE 'coroinha' END,
   approved=true WHERE id=p_user;
  UPDATE neon_auth.session SET "expiresAt"=now(),"updatedAt"=now()
   WHERE "userId" IN (SELECT subject::uuid FROM migration_private.identity_map WHERE provider='neon' AND profile_id=p_user)
    AND "expiresAt">now();
  RETURN 'Perfil atualizado';
 ELSIF p_action IN ('delete','ban') THEN
  IF NOT public.has_site_permission('manage_users') THEN RAISE EXCEPTION 'Sem permissão para gerenciar usuários' USING ERRCODE='42501'; END IF;
  IF v_role='desenvolvedor' THEN RAISE EXCEPTION 'Conta de Desenvolvedor protegida' USING ERRCODE='42501'; END IF;
  IF p_action='ban' THEN
   PERFORM pg_advisory_xact_lock(hashtextextended(v_email,8271));
   INSERT INTO public.banned_emails(email,banned_by) VALUES(v_email,auth.uid()) ON CONFLICT (email) DO NOTHING;
  END IF;
  PERFORM migration_private.remove_site_account(p_user);
  RETURN CASE WHEN p_action='ban' THEN 'E-mail banido e conta excluída' ELSE 'Conta excluída; novo cadastro permitido' END;
 ELSE RAISE EXCEPTION 'Ação inválida' USING ERRCODE='22023'; END IF;
END $function$;

CREATE OR REPLACE FUNCTION public.protect_profile()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
BEGIN
 IF NEW.id IS DISTINCT FROM OLD.id OR NEW.email IS DISTINCT FROM OLD.email OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
  RAISE EXCEPTION 'Identidade imutável' USING ERRCODE='42501';
 END IF;
 IF (NEW.role IS DISTINCT FROM OLD.role OR NEW.coordination_group IS DISTINCT FROM OLD.coordination_group)
  AND NOT public.is_developer()
  AND NOT (public.has_site_permission('manage_users')
   AND current_setting('app.delegated_role_change_target',true)=OLD.id::text) THEN
  RAISE EXCEPTION 'Somente desenvolvedor altera papéis e grupos' USING ERRCODE='42501';
 END IF;
 IF (NEW.approved IS DISTINCT FROM OLD.approved OR NEW.notes IS DISTINCT FROM OLD.notes)
  AND NOT public.can_manage_profile(OLD.id) THEN
  RAISE EXCEPTION 'Sem permissão para administrar este cadastro' USING ERRCODE='42501';
 END IF;
 IF NOT public.is_developer() AND OLD.role IN ('coordenadora','desenvolvedor')
   AND NEW.approved IS DISTINCT FROM OLD.approved THEN
  RAISE EXCEPTION 'Conta administrativa protegida' USING ERRCODE='42501';
 END IF;
 RETURN NEW;
END $function$;
