-- Safe readiness of the four existing approved profiles; never show email,
-- password material, Neon user IDs or auth reset tokens.
SELECT p.role,count(*)::int AS original_profiles,
 count(*) FILTER(WHERE u.id IS NOT NULL)::int AS neon_mapped,
 count(*) FILTER(WHERE u.id IS NOT NULL AND lower(u.email)=lower(p.email))::int AS email_match,
 count(*) FILTER(WHERE u."emailVerified")::int AS verified_email,
 count(*) FILTER(WHERE EXISTS(SELECT 1 FROM neon_auth.account a
   WHERE a."userId"=u.id AND a.password IS NOT NULL))::int AS passwords_ready
FROM public.profiles p
LEFT JOIN migration_private.identity_map i ON i.provider='neon' AND i.profile_id=p.id
LEFT JOIN neon_auth."user" u ON u.id::text=i.subject
WHERE p.role IN('coordenadora','desenvolvedor') AND p.approved
 AND p.email !~* '@(example|test)[.]invalid$'
GROUP BY p.role ORDER BY p.role;
