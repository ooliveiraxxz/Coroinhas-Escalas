-- Coroinhas: Neon branch readiness inventory (read-only).
-- Important: known @example.invalid / @test.invalid profiles are identified for
-- reporting ONLY. Never use this heuristic to authorize deletion.
-- Execute against authorized staging branch br-rough-hill-bcj6lzt1.
-- All results are aggregate counts; no names, emails, tokens or keys are exposed.
WITH originals AS (
 SELECT p.id,p.email FROM public.profiles p
 WHERE p.email IS NOT NULL AND p.email !~* '@(example|test)[.]invalid$'
), linked AS (
 SELECT p.id,p.email,u.id AS auth_id,u.email AS auth_email
 FROM originals p
 LEFT JOIN migration_private.identity_map m ON m.provider='neon' AND m.profile_id=p.id
 LEFT JOIN neon_auth."user" u ON u.id::text=m.subject
), credentials AS (
 SELECT l.id,l.auth_id,l.email,l.auth_email,
 EXISTS(SELECT 1 FROM neon_auth.account a
        WHERE a."userId"=l.auth_id AND a.password IS NOT NULL) AS has_password
 FROM linked l
)
SELECT
 (SELECT count(*) FROM public.profiles)::int AS all_profiles,
 (SELECT count(*) FROM originals)::int AS original_profiles,
 (SELECT count(*) FROM public.profiles p WHERE p.email ~* '@(example|test)[.]invalid$')::int AS fixture_profiles,
 (SELECT count(*) FROM credentials WHERE auth_id IS NULL)::int AS original_missing_auth_mapping,
 (SELECT count(*) FROM credentials WHERE lower(email) IS DISTINCT FROM lower(auth_email))::int AS original_email_mismatch,
 (SELECT count(*) FROM credentials WHERE has_password)::int AS original_password_ready,
 (SELECT count(*) FROM neon_auth."user")::int AS auth_users,
 (SELECT count(*) FROM neon_auth.session WHERE "expiresAt">now())::int AS active_sessions,
 (SELECT count(*) FROM public.push_subscriptions s LEFT JOIN public.profiles p
  ON p.id=s.user_id WHERE p.id IS NULL)::int AS orphan_subscriptions,
 (SELECT count(*) FROM migration_private.push_outbox WHERE state<>'suppressed')::int AS unsuppressed_push_jobs,
 (SELECT count(*) FROM migration_private.push_delivery_attempts)::int AS push_attempts,
 (SELECT count(*) FROM pg_tables WHERE schemaname='public' AND rowsecurity)::int AS rls_protected_tables,
 (SELECT count(*) FROM pg_policies WHERE schemaname='public')::int AS public_policies,
 ((SELECT count(*) FROM credentials WHERE has_password)=(SELECT count(*) FROM originals)
  AND (SELECT count(*) FROM credentials WHERE auth_id IS NULL)=0
  AND (SELECT count(*) FROM credentials WHERE lower(email) IS DISTINCT FROM lower(auth_email))=0)
  AS existing_accounts_ready;
