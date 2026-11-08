-- EXECUTAR SOMENTE APOS CADASTRO E VERIFICACAO DO E-MAIL DO DESENVOLVEDOR.
-- Branch: br-rough-hill-bcj6lzt1. Uso administrativo único, nunca na aplicação.
-- Nao cria senhas nem permite autoelevação por usuarios comuns.
DO $bootstrap$
DECLARE
  v_auth uuid;
  v_profile uuid;
  v_role text;
  v_approved boolean;
BEGIN
  IF current_database() <> 'coroinhas'
     OR NOT EXISTS (SELECT 1 FROM migration_private.environment WHERE branch_id='br-rough-hill-bcj6lzt1')
     OR NOT EXISTS (SELECT 1 FROM migration_private.cutover_reset_archive_20261108)
  THEN
    RAISE EXCEPTION 'Bootstrap permitido somente na homologacao limpa prevista';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('coroinhas-first-developer-bootstrap',0));

  IF EXISTS (SELECT 1 FROM public.profiles WHERE approved AND role='desenvolvedor')
  THEN RAISE EXCEPTION 'Ja existe desenvolvedor aprovado; nao executar bootstrap novamente'; END IF;

  SELECT u.id INTO STRICT v_auth
    FROM neon_auth."user" u
   WHERE lower(u.email)='santanalucas220210@gmail.com'
     AND u."emailVerified" IS TRUE
     AND coalesce(u.banned,false) IS FALSE
     AND EXISTS(SELECT 1 FROM neon_auth.account a
                  WHERE a."userId"=u.id AND a."providerId"='credential'
                    AND a.password IS NOT NULL);

  SELECT i.profile_id INTO STRICT v_profile
    FROM migration_private.identity_map i
   WHERE i.provider='neon' AND i.subject=v_auth::text;

  SELECT role,approved INTO STRICT v_role,v_approved
    FROM public.profiles
   WHERE id=v_profile AND lower(email)='santanalucas220210@gmail.com'
   FOR UPDATE;

  IF v_role NOT IN ('coroinha','pai') OR v_approved IS DISTINCT FROM false
  THEN RAISE EXCEPTION 'Perfil nao e um cadastro novo pendente'; END IF;

  -- O primeiro desenvolvedor ainda nao pode satisfazer o guard_profile;
  -- o owner suspende somente este trigger sob lock exclusivo nesta transacao.
  LOCK TABLE public.profiles IN ACCESS EXCLUSIVE MODE;
  ALTER TABLE public.profiles DISABLE TRIGGER guard_profile;
  UPDATE public.profiles
     SET role='desenvolvedor', approved=true
   WHERE id=v_profile;
  ALTER TABLE public.profiles ENABLE TRIGGER guard_profile;
  IF NOT EXISTS(SELECT 1 FROM public.profiles WHERE id=v_profile AND role='desenvolvedor' AND approved)
  THEN RAISE EXCEPTION 'Falha ao confirmar promocao';END IF;
END
$bootstrap$;

-- Consulta de confirmacao (executar separadamente):
-- SELECT role,approved FROM public.profiles
-- WHERE email='santanalucas220210@gmail.com';