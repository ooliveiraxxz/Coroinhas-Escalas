-- Safe read-only regression: never enables push or emits notifications.
DO $test$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM migration_private.environment
    WHERE branch_id='br-rough-hill-bcj6lzt1')
 THEN RAISE EXCEPTION 'Wrong branch'; END IF;
 IF (SELECT enabled FROM migration_private.push_runtime WHERE id=true)
 THEN RAISE EXCEPTION 'Staging push must be disabled';END IF;
 IF EXISTS(SELECT 1 FROM migration_private.push_claim(10))
 THEN RAISE EXCEPTION 'Disabled push returned a delivery';END IF;
 IF (SELECT rolcanlogin OR rolsuper OR rolbypassrls FROM pg_roles
     WHERE rolname='coroinhas_push_worker')
 THEN RAISE EXCEPTION 'Push role must be disabled and unprivileged';END IF;
 IF NOT has_function_privilege('coroinhas_push_worker',
     'migration_private.push_claim(integer)','EXECUTE')
 THEN RAISE EXCEPTION 'Push role cannot claim';END IF;
 IF has_function_privilege('coroinhas_gateway',
     'migration_private.push_claim(integer)','EXECUTE')
 THEN RAISE EXCEPTION 'Gateway must not claim push';END IF;
 IF has_table_privilege('coroinhas_push_worker',
     'migration_private.push_runtime','SELECT')
 THEN RAISE EXCEPTION 'Push role must not read configuration directly';END IF;
 IF has_table_privilege('coroinhas_push_worker',
     'migration_private.push_delivery_attempts','UPDATE')
 THEN RAISE EXCEPTION 'Push role must not modify ledger directly';END IF;
END $test$;
