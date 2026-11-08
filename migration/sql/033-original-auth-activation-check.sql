-- Read-only and privacy-preserving activation/readiness check.
-- Does NOT reset passwords, verify email, alter roles or send email.
WITH originals AS (
 SELECT p.id,p.role,p.email,p.approved,
        i.subject,u.id AS auth_id,u.email AS auth_email,u."emailVerified" AS verified,
        EXISTS(SELECT 1 FROM neon_auth.account a
               WHERE a."userId"=u.id AND a."providerId"='credential'
                 AND a.password IS NOT NULL) AS password_ready
 FROM public.profiles p
 LEFT JOIN migration_private.identity_map i ON i.provider='neon' AND i.profile_id=p.id
 LEFT JOIN neon_auth."user" u ON u.id::text=i.subject
 WHERE p.role IN ('coordenadora','desenvolvedor')
  AND p.email !~* '@(example|test)[.]invalid$'
)
SELECT count(*)::int total,
 count(*) FILTER(WHERE approved)::int approved,
 count(*) FILTER(WHERE auth_id IS NOT NULL)::int linked,
 count(*) FILTER(WHERE lower(email)=lower(auth_email))::int matching_email,
 count(*) FILTER(WHERE verified)::int verified_email,
 count(*) FILTER(WHERE password_ready)::int activated_password,
 count(*) FILTER(WHERE EXISTS(SELECT 1 FROM public.banned_emails b WHERE lower(b.email)=lower(originals.email)))::int banned,
 count(DISTINCT id)::int distinct_profile_ids,
 count(DISTINCT auth_id)::int distinct_auth_ids,
 count(*)=4 AND count(*) FILTER(WHERE approved)=4
 AND count(*) FILTER(WHERE auth_id IS NOT NULL)=4
 AND count(*) FILTER(WHERE lower(email)=lower(auth_email))=4
 AND count(DISTINCT id)=4 AND count(DISTINCT auth_id)=4 AS identity_integrity_ok
FROM originals;
