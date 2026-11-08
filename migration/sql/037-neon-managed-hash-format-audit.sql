-- Neon staging ONLY. Read-only password hash format inspection.
-- Never print hashed credentials, salts, emails or identity IDs.
DO $guard$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM migration_private.environment WHERE id=true
 AND branch_id='br-rough-hill-bcj6lzt1') THEN
 RAISE EXCEPTION 'Wrong branch'; END IF;
END $guard$;
SELECT count(*)::int credential_accounts,
 count(*) FILTER(WHERE password IS NOT NULL)::int with_password,
 count(*) FILTER(WHERE password ~ '^[0-9a-f]{32}:[0-9a-f]{128}$')::int scrypt_compatible,
 count(*) FILTER(WHERE password LIKE '$2a$%' OR password LIKE '$2b$%')::int bcrypt,
 count(*) FILTER(WHERE password IS NOT NULL AND
  password !~ '^[0-9a-f]{32}:[0-9a-f]{128}$')::int other_hash_format
FROM neon_auth.account WHERE "providerId"='credential';