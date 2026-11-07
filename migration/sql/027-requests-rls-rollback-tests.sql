-- Real RLS request test, all fixture writes rolled back by an inner PL/pgSQL
-- exception block. No persistent users, masses or requests.
DO $test$
DECLARE uid uuid:='00000000-0000-4000-8000-000000008781';
        mid uuid:='00000000-0000-4000-8000-000000008782';
        denied boolean:=false;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM migration_private.environment WHERE id=true
   AND branch_id IN('br-rough-hill-bcj6lzt1','br-odd-bread-bc1jxzsh'))
 THEN RAISE EXCEPTION 'Wrong branch'; END IF;
 BEGIN
  INSERT INTO public.profiles(id,name,email,role,approved)
   VALUES(uid,'Request RLS rollback fixture','request-rls-rollback@example.invalid','coroinha',true);
  INSERT INTO public.masses(id,title,starts_at,location,published)
   VALUES(mid,'RLS transaction fixture',now()+interval '2 days','Teste',true);
  PERFORM set_config('app.user_id',uid::text,true);
  EXECUTE 'SET LOCAL ROLE coroinhas_app';
  -- A published future mass allows an approved coroinha's ordinary request.
  INSERT INTO public.requests(mass_id,user_id,type) VALUES(mid,uid,'servir');
  -- Substitution without an assignment must be rejected by RLS.
  BEGIN
   INSERT INTO public.requests(mass_id,user_id,type) VALUES(mid,uid,'substituir');
  EXCEPTION WHEN insufficient_privilege THEN denied:=true;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'Invalid substitution permitted'; END IF;
  RAISE EXCEPTION 'ROLLBACK_TEST_SUCCESS';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'ROLLBACK_TEST_SUCCESS' THEN RAISE;END IF;
 END;
 IF EXISTS(SELECT 1 FROM public.profiles WHERE id=uid) THEN
  RAISE EXCEPTION 'Fixture persisted'; END IF;
END $test$;
