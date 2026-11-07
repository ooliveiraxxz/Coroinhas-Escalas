-- Read-only clean rehearsal inventory: authorized independent Neon branch.
-- This does not assert a production-ready backup or an exhaustive live sync.
WITH marker AS (
 SELECT branch_id FROM migration_private.environment WHERE id=true
), checks AS (
 SELECT
  (SELECT count(*)::int FROM public.profiles) AS profiles,
  (SELECT count(*)::int FROM public.audit_log) AS audit_rows,
  (SELECT count(*)::int FROM public.site_updates) AS site_updates,
  (SELECT count(*)::int FROM migration_private.identity_map WHERE provider='neon') AS neon_links,
  (SELECT count(*)::int FROM neon_auth."user") AS neon_auth_users,
  (SELECT count(*)::int FROM public.push_subscriptions s LEFT JOIN public.profiles p ON p.id=s.user_id WHERE p.id IS NULL) AS orphan_push,
  (SELECT count(*)::int FROM pg_policies WHERE schemaname='public') AS policies,
  (SELECT count(*)::int FROM pg_tables WHERE schemaname='public' AND rowsecurity) AS rls_tables,
  (SELECT count(*)::int FROM public.profiles WHERE role='desenvolvedor') AS developers,
  (SELECT count(*)::int FROM public.profiles WHERE role='coordenadora') AS coordinators
)
SELECT marker.branch_id, checks.*,
 marker.branch_id='br-odd-bread-bc1jxzsh'
 AND checks.profiles=4 AND checks.neon_links=4
 AND checks.developers=1 AND checks.coordinators=3
 AND checks.orphan_push=0 AND checks.rls_tables=15
 AND checks.policies=33 AS structural_readiness
FROM marker CROSS JOIN checks;
