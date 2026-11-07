-- Auditoria sem escrita: executar apenas em migration-coroinhas-20261106.
DO $$
BEGIN
 IF NOT EXISTS (SELECT 1 FROM migration_private.environment WHERE branch_id='br-rough-hill-bcj6lzt1') THEN RAISE EXCEPTION 'Branch incorreta'; END IF;
 IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname IN ('coroinhas_app','coroinhas_gateway') AND (rolsuper OR rolbypassrls OR rolcreaterole OR rolcreatedb)) THEN RAISE EXCEPTION 'Papel com privilégios excessivos'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='coroinhas_gateway' AND rolcanlogin) THEN RAISE EXCEPTION 'Gateway indisponível'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='coroinhas_app' AND NOT rolcanlogin) THEN RAISE EXCEPTION 'Papel RLS permite login'; END IF;
 IF (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind='r' AND c.relrowsecurity) <> 15 THEN RAISE EXCEPTION 'RLS ausente em alguma tabela'; END IF;
 IF EXISTS (SELECT 1 FROM migration_private.identity_map m LEFT JOIN public.profiles p ON p.id=m.profile_id WHERE p.id IS NULL) THEN RAISE EXCEPTION 'Mapa de identidade órfão'; END IF;
 IF EXISTS (SELECT 1 FROM migration_private.identity_map m JOIN neon_auth."user" a ON m.provider='neon' AND m.subject=a.id::text JOIN public.profiles p ON p.id=m.profile_id WHERE lower(a.email) IS DISTINCT FROM lower(p.email)) THEN RAISE EXCEPTION 'Divergência de e-mails vinculados'; END IF;
 IF (SELECT count(*) FROM pg_policies WHERE schemaname='public' AND tablename='screen_announcement_dismissals' AND cmd IN ('INSERT','UPDATE') AND with_check LIKE '%target_role%') <> 2 THEN RAISE EXCEPTION 'Destinatário de aviso sem validação'; END IF;
END $$;
SELECT (SELECT count(*) FROM public.profiles) AS profiles,
 (SELECT count(*) FROM migration_private.identity_map WHERE provider='neon') AS mapped_profiles,
 (SELECT count(*) FROM neon_auth."user") AS auth_accounts,
 (SELECT count(*) FROM neon_auth.session WHERE "expiresAt">now()) AS active_sessions,
 'PASSOU: verificações estáticas de segurança; sem testar login real' AS status;
