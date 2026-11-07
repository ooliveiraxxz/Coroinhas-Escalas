BEGIN;
INSERT INTO profiles(id,name,email,role,approved) VALUES ('00000000-0000-4000-8000-000000000101','Fixture server','server@example.invalid','coroinha',true),('00000000-0000-4000-8000-000000000102','Fixture other','other@example.invalid','coroinha',true),('00000000-0000-4000-8000-000000000103','Fixture parent','parent@example.invalid','pai',true),('00000000-0000-4000-8000-000000000104','Fixture pending','pending@example.invalid','coroinha',false),('00000000-0000-4000-8000-000000000105','Fixture coord','coord@example.invalid','coordenadora',true),('00000000-0000-4000-8000-000000000106','Fixture dev','dev@example.invalid','desenvolvedor',true);

INSERT INTO masses(id,title,starts_at,published) VALUES('00000000-0000-4000-8000-000000000201','Fixture public',((now() AT TIME ZONE 'America/Sao_Paulo')::date + time '23:59') AT TIME ZONE 'America/Sao_Paulo',true),('00000000-0000-4000-8000-000000000202','Fixture draft',now()+interval '2 days',false);

INSERT INTO assignments(id,mass_id,function_name,server_id) VALUES('00000000-0000-4000-8000-000000000301','00000000-0000-4000-8000-000000000201','Fixture','00000000-0000-4000-8000-000000000101');

INSERT INTO notifications(id,user_id,title,body) VALUES('00000000-0000-4000-8000-000000000401','00000000-0000-4000-8000-000000000101','Fixture','Hello'),('00000000-0000-4000-8000-000000000402','00000000-0000-4000-8000-000000000102','Fixture','Other');

SET LOCAL ROLE coroinhas_app;

DO $$ BEGIN IF EXISTS(SELECT 1 FROM profiles) OR EXISTS(SELECT 1 FROM masses) THEN RAISE EXCEPTION 'Anonymous leaked rows';END IF;END $$;

SELECT set_config('app.user_id','00000000-0000-4000-8000-000000000104',true);

DO $$ BEGIN IF (SELECT count(*) FROM profiles)<>1 OR EXISTS(SELECT 1 FROM masses) THEN RAISE EXCEPTION 'Pending access violation';END IF;END $$;

SELECT set_config('app.user_id','00000000-0000-4000-8000-000000000101',true);

DO $$ BEGIN IF EXISTS(SELECT 1 FROM masses WHERE id='00000000-0000-4000-8000-000000000202') THEN RAISE EXCEPTION 'Draft leaked';END IF;IF (SELECT count(*) FROM notifications)<>1 THEN RAISE EXCEPTION 'Other notification leaked';END IF;IF EXISTS(SELECT 1 FROM audit_log) THEN RAISE EXCEPTION 'Audit leaked';END IF;END $$;

DO $$ BEGIN BEGIN UPDATE profiles SET role='desenvolvedor' WHERE id='00000000-0000-4000-8000-000000000101';RAISE EXCEPTION 'Escalation allowed';EXCEPTION WHEN insufficient_privilege THEN NULL;END;END $$;

SELECT mark_notification_seen('00000000-0000-4000-8000-000000000401');

DO $$ BEGIN IF NOT (SELECT seen FROM notifications WHERE id='00000000-0000-4000-8000-000000000401') THEN RAISE EXCEPTION 'Seen failed';END IF;END $$;

SELECT respond_assignment('00000000-0000-4000-8000-000000000301','confirmar','');

DO $$ BEGIN IF (SELECT status FROM assignments WHERE id='00000000-0000-4000-8000-000000000301')<>'confirmado' THEN RAISE EXCEPTION 'Confirm failed';END IF;END $$;

SELECT set_config('app.user_id','00000000-0000-4000-8000-000000000102',true);

DO $$ BEGIN BEGIN PERFORM respond_assignment('00000000-0000-4000-8000-000000000301','desmarcar','Fixture');RAISE EXCEPTION 'Ownership failed' USING ERRCODE='XX000';EXCEPTION WHEN raise_exception THEN NULL;END;END $$;

SELECT set_config('app.user_id','00000000-0000-4000-8000-000000000101',true);

SELECT respond_assignment('00000000-0000-4000-8000-000000000301','desmarcar','Teste isolado');

DO $$ BEGIN IF (SELECT status FROM assignments WHERE id='00000000-0000-4000-8000-000000000301')<>'desmarcado' THEN RAISE EXCEPTION 'Withdrawal failed';END IF;END $$;

SELECT set_config('app.user_id','00000000-0000-4000-8000-000000000103',true);

DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM masses WHERE id='00000000-0000-4000-8000-000000000201') THEN RAISE EXCEPTION 'Parent read failed';END IF;BEGIN INSERT INTO masses(title,starts_at) VALUES('Forbidden',now());RAISE EXCEPTION 'Parent write allowed';EXCEPTION WHEN insufficient_privilege THEN NULL;END;END $$;

SELECT set_config('app.user_id','00000000-0000-4000-8000-000000000105',true);

DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM masses WHERE id='00000000-0000-4000-8000-000000000202') THEN RAISE EXCEPTION 'Coordinator draft missing';END IF;END $$;

DO $$ BEGIN BEGIN UPDATE profiles SET role='desenvolvedor' WHERE id='00000000-0000-4000-8000-000000000105';RAISE EXCEPTION 'Coordinator escalation allowed';EXCEPTION WHEN insufficient_privilege THEN NULL;END;END $$;

UPDATE profiles SET approved=true WHERE id='00000000-0000-4000-8000-000000000104';

SELECT set_config('app.user_id','00000000-0000-4000-8000-000000000106',true);

SELECT developer_usage_summary() IS NOT NULL AS usage_ok;

DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM audit_log WHERE record_id='00000000-0000-4000-8000-000000000301') THEN RAISE EXCEPTION 'Audit missing';END IF;END $$;

RESET ROLE;

DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM migration_private.push_outbox) OR EXISTS(SELECT 1 FROM migration_private.push_outbox WHERE state<>'suppressed') THEN RAISE EXCEPTION 'Push isolation failure';END IF;END $$;

ROLLBACK;
