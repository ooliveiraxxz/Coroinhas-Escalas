-- Somente leitura. Execute na branch de homologação do Neon.
-- Nunca cria, atualiza, libera, verifica ou exclui usuários.
WITH auth_state AS (
 SELECT
   count(*)::integer AS auth_users,
   count(*) FILTER (WHERE a."emailVerified" IS TRUE)::integer AS verified_users,
   count(*) FILTER (WHERE m.profile_id IS NOT NULL)::integer AS mapped_users,
   count(*) FILTER (WHERE m.profile_id IS NULL)::integer AS unmapped_users,
   count(*) FILTER (WHERE m.profile_id IS NOT NULL AND p.id IS NULL)::integer AS orphan_mappings,
   count(*) FILTER (WHERE p.id IS NOT NULL AND lower(p.email) IS DISTINCT FROM lower(a.email))::integer AS inconsistent_emails
 FROM neon_auth."user" a
 LEFT JOIN migration_private.identity_map m
   ON m.provider='neon' AND m.subject=a.id::text
 LEFT JOIN public.profiles p ON p.id=m.profile_id
), profiles_state AS (
 SELECT
   count(*)::integer AS profiles,
   count(*) FILTER (WHERE approved)::integer AS approved_profiles
 FROM public.profiles
), session_state AS (
 SELECT count(*) FILTER (WHERE "expiresAt" > now())::integer AS active_sessions
 FROM neon_auth.session
)
SELECT
 a.auth_users, p.profiles, p.approved_profiles,
 a.mapped_users, a.unmapped_users, a.verified_users,
 a.orphan_mappings, a.inconsistent_emails, s.active_sessions,
 (a.mapped_users=p.profiles AND a.unmapped_users=0
  AND a.verified_users=a.auth_users AND a.orphan_mappings=0
  AND a.inconsistent_emails=0) AS identity_inventory_ready,
 'ATENCAO: inventario nao comprova login, recuperacao de senha, autorizacao nem seguranca da sessao'::text AS warning
FROM auth_state a CROSS JOIN profiles_state p CROSS JOIN session_state s;
