-- Consulta somente leitura. Executar EXCLUSIVAMENTE no Neon de homologação.
-- Não autoriza migração; fornece indicadores técnicos para decisão humana.
WITH checks AS (
 SELECT
  EXISTS(SELECT 1 FROM migration_private.environment WHERE branch_id='br-rough-hill-bcj6lzt1') AS correct_branch,
  (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind='r') AS public_tables,
  (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind='r' AND c.relrowsecurity) AS rls_tables,
  (SELECT count(*) FROM pg_policies WHERE schemaname='public') AS rls_policies,
  (SELECT count(*) FROM migration_private.identity_map WHERE provider='neon') AS neon_mapped_profiles,
  (SELECT count(*) FROM public.profiles) AS profiles,
  (SELECT count(*) FROM neon_auth."user") AS neon_accounts,
  (SELECT count(*) FROM neon_auth."user" a LEFT JOIN migration_private.identity_map m ON m.provider='neon' AND m.subject=a.id::text WHERE m.subject IS NULL) AS unlinked_accounts,
  (SELECT count(*) FROM neon_auth.session WHERE "expiresAt">now()) AS active_sessions,
  (SELECT count(*) FROM migration_private.identity_map m JOIN neon_auth."user" a ON m.provider='neon' AND m.subject=a.id::text JOIN public.profiles p ON p.id=m.profile_id WHERE lower(a.email) IS DISTINCT FROM lower(p.email)) AS mismatched_emails,
  (SELECT count(*) FROM public.push_subscriptions s LEFT JOIN public.profiles p ON p.id=s.user_id WHERE p.id IS NULL) AS orphan_push,
  (SELECT count(*) FROM pg_constraint WHERE conrelid='public.push_subscriptions'::regclass AND conname='push_subscriptions_profile_fkey' AND convalidated) AS validated_push_fks,
  (SELECT count(*) FROM migration_private.push_outbox WHERE state NOT IN ('suppressed')) AS outgoing_push_jobs,
  has_schema_privilege('coroinhas_app','public','CREATE') AS app_can_create,
  (SELECT rolbypassrls OR rolsuper FROM pg_roles WHERE rolname='coroinhas_gateway') AS gateway_privileged
)
SELECT *,
 correct_branch AND public_tables=15 AND rls_tables=15 AND rls_policies=33
 AND neon_mapped_profiles=profiles AND mismatched_emails=0
 AND orphan_push=0 AND validated_push_fks=1
 AND NOT app_can_create AND NOT gateway_privileged AS static_checks_ok,
 'Não valida cadastro, login, notificações, E2E nem prontidão de produção' AS limitation
FROM checks;
