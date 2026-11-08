-- Read-only staging readiness. Single SELECT; reports false for non-staging.
WITH branch_marker AS (SELECT EXISTS(SELECT 1 FROM migration_private.environment WHERE id=true AND branch_id='br-rough-hill-bcj6lzt1') on_staging), originals AS (
 SELECT p.id,p.email,p.approved,p.role,i.subject,u.id auth_id,u.email auth_email,
 EXISTS(SELECT 1 FROM neon_auth.account a
        WHERE a."userId"=u.id AND a."providerId"='credential' AND a.password IS NOT NULL) password_ready
 FROM public.profiles p
 LEFT JOIN migration_private.identity_map i ON i.profile_id=p.id AND i.provider='neon'
 LEFT JOIN neon_auth."user" u ON u.id::text=i.subject
 WHERE p.role IN ('coordenadora','desenvolvedor')
 AND p.email !~* '@(example|test)[.]invalid$'
)
SELECT
 (SELECT on_staging FROM branch_marker) on_staging,
 (SELECT count(*)::int FROM pg_policies WHERE schemaname='public') AS public_rls_policies,
 (SELECT count(*)::int FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='public' AND c.relkind='r' AND c.relrowsecurity)::int AS rls_tables,
 (SELECT count(*)::int FROM originals) original_profiles,
 (SELECT count(*)::int FROM originals WHERE approved AND auth_id IS NOT NULL
  AND lower(email)=lower(auth_email)) linked_profiles,
 (SELECT count(*)::int FROM originals WHERE password_ready) password_ready,
 (SELECT enabled FROM migration_private.push_runtime WHERE id=true) push_enabled,
 (SELECT count(*)::int FROM migration_private.push_delivery_attempts) push_attempts,
 (SELECT count(*)::int FROM public.assignments a LEFT JOIN public.masses m ON m.id=a.mass_id
  WHERE m.id IS NULL) orphan_assignments,
 (SELECT count(*)::int FROM migration_private.identity_map i
  LEFT JOIN public.profiles p ON p.id=i.profile_id WHERE p.id IS NULL) orphan_identities,
 (SELECT rolcanlogin FROM pg_roles WHERE rolname='coroinhas_push_worker') push_role_can_login,
 (SELECT rolbypassrls FROM pg_roles WHERE rolname='coroinhas_gateway') gateway_bypass_rls,
 ((SELECT on_staging FROM branch_marker) AND (SELECT count(*) FROM originals)=4 AND
  (SELECT count(*) FROM originals WHERE approved AND auth_id IS NOT NULL
    AND lower(email)=lower(auth_email))=4 AND
  (SELECT count(*) FROM pg_policies WHERE schemaname='public')>=33 AND
  (SELECT count(*) FROM public.assignments a LEFT JOIN public.masses m ON m.id=a.mass_id
    WHERE m.id IS NULL)=0 AND
  (SELECT count(*) FROM migration_private.identity_map i
   LEFT JOIN public.profiles p ON p.id=i.profile_id WHERE p.id IS NULL)=0 AND
  (SELECT rolbypassrls FROM pg_roles WHERE rolname='coroinhas_gateway')=false
 ) AS staging_security_gates_pass;
