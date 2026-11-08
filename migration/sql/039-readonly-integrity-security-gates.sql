-- Homologação apenas; SQL SOMENTE LEITURA.
-- Validado via Neon SQL connector em 07/11/2026.
-- Não substitui testes E2E, auditoria de dados, backup ou sincronização final.
WITH checks AS (
 SELECT
 (SELECT count(*)::int FROM public.assignments a LEFT JOIN public.masses m ON m.id=a.mass_id WHERE m.id IS NULL) AS orphan_masses,
 (SELECT count(*)::int FROM public.assignments a LEFT JOIN public.profiles p ON p.id=a.server_id WHERE a.server_id IS NOT NULL AND p.id IS NULL) AS orphan_assignees,
 (SELECT count(*)::int FROM public.requests r LEFT JOIN public.profiles p ON p.id=r.user_id WHERE p.id IS NULL) AS orphan_request_users,
 (SELECT count(*)::int FROM public.push_subscriptions s LEFT JOIN public.profiles p ON p.id=s.user_id WHERE p.id IS NULL) AS orphan_push_users,
 (SELECT count(*)::int FROM migration_private.identity_map i LEFT JOIN public.profiles p ON p.id=i.profile_id WHERE p.id IS NULL) AS orphan_identity_maps,
 (SELECT count(*)::int FROM (SELECT lower(email) FROM public.profiles GROUP BY lower(email) HAVING count(*)>1) d) AS duplicate_emails,
 (SELECT count(*)::int FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind='r' AND NOT c.relrowsecurity) AS public_tables_without_rls,
 (SELECT count(*)::int FROM pg_roles WHERE rolname IN ('coroinhas_app','coroinhas_gateway') AND rolbypassrls) AS unsafe_bypass_roles,
 (SELECT coalesce('security_invoker=true'=ANY(c.reloptions),false) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relname='profile_directory') AS profile_view_invoker,
 (SELECT has_table_privilege('coroinhas_app','public.profile_directory','SELECT')) AS profile_directory_readable,
 (SELECT has_table_privilege('coroinhas_app','public.profiles','DELETE')) AS app_can_delete_profiles,
 (SELECT has_table_privilege('coroinhas_app','public.audit_log','INSERT')) AS app_can_insert_audit,
 (SELECT enabled FROM migration_private.push_runtime WHERE id=true) AS push_enabled
)
SELECT *,
 (orphan_masses=0 AND orphan_assignees=0 AND orphan_request_users=0 AND orphan_push_users=0
 AND orphan_identity_maps=0 AND duplicate_emails=0 AND public_tables_without_rls=0
 AND unsafe_bypass_roles=0 AND profile_view_invoker AND profile_directory_readable
 AND NOT app_can_delete_profiles AND NOT app_can_insert_audit AND NOT push_enabled)
 AS staging_integrity_security_pass
FROM checks;
