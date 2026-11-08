-- Rollback-only negative RLS and grants smoke test. All fixtures are
-- created and rolled back within the exception subtransaction.
DO $test$
DECLARE uid uuid:='00000000-0000-4000-8000-000000008913';
        denied_role boolean:=false; denied_delete boolean:=false;
        denied_email boolean:=false;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM migration_private.environment WHERE id=true
  AND branch_id IN('br-rough-hill-bcj6lzt1','br-odd-bread-bc1jxzsh'))
 THEN RAISE EXCEPTION 'Wrong branch'; END IF;
 BEGIN
  INSERT INTO public.profiles(id,name,email,role,approved)
   VALUES(uid,'RLS rollback fixture','rls-rollback-20261107@example.invalid','coroinha',true);
  PERFORM set_config('app.user_id',uid::text,true);
  EXECUTE 'SET LOCAL ROLE coroinhas_app';
  -- Users must not promote themselves.
  BEGIN
   UPDATE public.profiles SET role='coordenadora' WHERE id=uid;
  EXCEPTION WHEN insufficient_privilege THEN denied_role:=true;
  END;
  IF NOT denied_role THEN RAISE EXCEPTION 'A user changed their own role';END IF;
  -- Email immutability is additionally protected at the trigger level.
  BEGIN
   UPDATE public.profiles SET email='altered@example.invalid' WHERE id=uid;
  EXCEPTION WHEN insufficient_privilege THEN denied_email:=true;
  END;
  IF NOT denied_email THEN RAISE EXCEPTION 'A user changed their identity email';END IF;
  BEGIN
   DELETE FROM public.profiles WHERE id=uid;
  EXCEPTION WHEN insufficient_privilege THEN denied_delete:=true;
  END;
  IF NOT denied_delete THEN RAISE EXCEPTION 'Direct profile deletion was permitted';END IF;
  UPDATE public.profiles SET name='Permitted own name' WHERE id=uid;
  IF NOT EXISTS(SELECT 1 FROM public.profiles WHERE id=uid AND name='Permitted own name')
  THEN RAISE EXCEPTION 'Self-service name update unexpectedly denied';END IF;
  RAISE EXCEPTION 'ROLLBACK_FIXTURES_SUCCESS';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'ROLLBACK_FIXTURES_SUCCESS' THEN RAISE;END IF;
 END;
 IF EXISTS(SELECT 1 FROM public.profiles WHERE id=uid)
 THEN RAISE EXCEPTION 'Rollback fixture persisted';END IF;
END $test$;