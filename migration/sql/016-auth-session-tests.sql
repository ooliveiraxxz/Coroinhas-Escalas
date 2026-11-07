-- Isolated staging only; probe has no real profile. Roll back all changes.
BEGIN;
DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM migration_private.environment WHERE branch_id='br-rough-hill-bcj6lzt1') THEN RAISE EXCEPTION 'Wrong branch'; END IF; END $$;
INSERT INTO neon_auth.session(id,"userId",token,"expiresAt","updatedAt") SELECT '00000000-0000-4000-8000-000000007901',id,gen_random_uuid()::text,now()+interval '1 hour',now() FROM neon_auth."user" WHERE email='migration-probe-20261106@example.invalid';
SELECT migration_private.resolve_neon_identity((SELECT id FROM neon_auth."user" WHERE email='migration-probe-20261106@example.invalid'),'00000000-0000-4000-8000-000000007901','pai') IS NOT NULL AS bootstrap_ok;
DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM profiles WHERE email='migration-probe-20261106@example.invalid' AND role='pai' AND approved=false) THEN RAISE EXCEPTION 'Pending parent failed';END IF;END $$;
SELECT set_config('app.user_id',(SELECT id::text FROM profiles WHERE role='desenvolvedor' AND approved LIMIT 1),true);
SELECT public.developer_manage_user((SELECT id FROM profiles WHERE email='migration-probe-20261106@example.invalid'),'role','coroinha');
DO $$ BEGIN IF EXISTS(SELECT 1 FROM neon_auth.session WHERE id='00000000-0000-4000-8000-000000007901' AND "expiresAt">now()) THEN RAISE EXCEPTION 'Role session not expired';END IF; BEGIN PERFORM migration_private.resolve_neon_identity((SELECT id FROM neon_auth."user" WHERE email='migration-probe-20261106@example.invalid'),'00000000-0000-4000-8000-000000007901',NULL);RAISE EXCEPTION 'Expired accepted' USING ERRCODE='XX000';EXCEPTION WHEN insufficient_privilege THEN NULL;END;END $$;
UPDATE neon_auth.session SET "expiresAt"=now()+interval '1 hour' WHERE id='00000000-0000-4000-8000-000000007901';
SELECT public.developer_manage_user((SELECT id FROM profiles WHERE email='migration-probe-20261106@example.invalid'),'ban',NULL);
DO $$ BEGIN IF EXISTS(SELECT 1 FROM neon_auth.session WHERE id='00000000-0000-4000-8000-000000007901' AND "expiresAt">now()) OR EXISTS(SELECT 1 FROM profiles WHERE email='migration-probe-20261106@example.invalid' AND approved) THEN RAISE EXCEPTION 'Ban not applied'; END IF;END $$;
ROLLBACK;
