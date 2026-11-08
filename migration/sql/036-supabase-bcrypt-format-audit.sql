-- Source-only Supabase audit, READ ONLY. Never returns any hash or email.
-- Verify the current password-hash family and a synthetic bcrypt fixture.
WITH synthetic AS MATERIALIZED (
 SELECT crypt('synthetic_bcrypt_fixture_coroinhas_not_a_real_password_20261107',gen_salt('bf',10)) AS hash
)
SELECT
 (SELECT count(*)::int FROM auth.users) AS existing_users,
 (SELECT count(*)::int FROM auth.users
  WHERE encrypted_password LIKE '$2a$%' AND length(encrypted_password)=60) AS bcrypt_2a_60,
 (SELECT count(*)::int FROM auth.users WHERE encrypted_password IS NULL
    OR encrypted_password='') AS without_password_hash,
 (SELECT crypt('synthetic_bcrypt_fixture_coroinhas_not_a_real_password_20261107',hash)=hash FROM synthetic) AS fixture_valid_password_accepted,
 (SELECT crypt('incorrect_synthetic_fixture',hash)=hash FROM synthetic) AS fixture_wrong_password_accepted;