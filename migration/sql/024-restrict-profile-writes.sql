-- Restrict profile writes in Neon staging and the clean rehearsal branch.
-- Existing developer-managed role changes are performed through the privileged
-- audited developer_manage_user RPC; direct client role writes are unnecessary.
-- Existing app direct writes: own name/preferences, coordinator approval/notes.
-- record_site_access updates last_seen_at as a SECURITY DEFINER function.
DO $guard$
BEGIN
 IF NOT EXISTS (
  SELECT 1 FROM migration_private.environment
  WHERE id=true AND branch_id IN ('br-rough-hill-bcj6lzt1','br-odd-bread-bc1jxzsh')
 ) THEN RAISE EXCEPTION 'Unsupported Neon branch' USING ERRCODE='42501'; END IF;
END $guard$;

REVOKE UPDATE ON public.profiles FROM coroinhas_app;
GRANT UPDATE (name,photo_url,notification_preferences,notes,approved)
 ON public.profiles TO coroinhas_app;

-- Refuse client changes to creation and identity fields (even if a future
-- grant accidentally broadens access). Existing RLS still guards owner/role.
CREATE OR REPLACE FUNCTION public.protect_profile()
RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $fn$
BEGIN
 IF NEW.id IS DISTINCT FROM OLD.id OR NEW.email IS DISTINCT FROM OLD.email
    OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
  RAISE EXCEPTION 'Identidade e cadastro imutáveis' USING ERRCODE='42501';
 END IF;
 IF NEW.role IS DISTINCT FROM OLD.role AND NOT public.is_developer() THEN
  RAISE EXCEPTION 'Somente desenvolvedor altera papéis' USING ERRCODE='42501';
 END IF;
 IF (NEW.approved IS DISTINCT FROM OLD.approved OR NEW.notes IS DISTINCT FROM OLD.notes)
    AND NOT public.is_coordinator() THEN
  RAISE EXCEPTION 'Acesso restrito à coordenação' USING ERRCODE='42501';
 END IF;
 IF NOT public.is_developer() AND OLD.role IN ('coordenadora','desenvolvedor')
    AND NEW.approved IS DISTINCT FROM OLD.approved THEN
  RAISE EXCEPTION 'Somente desenvolvedor gerencia perfis especiais' USING ERRCODE='42501';
 END IF;
 RETURN NEW;
END $fn$;
