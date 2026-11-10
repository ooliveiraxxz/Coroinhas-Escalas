-- Rollback-only cross-role RLS proof on isolated Neon branches.
-- Fixtures and side effects are reverted before the transaction finishes.
DO $test$
DECLARE parent uuid:='00000000-0000-4000-8000-000000008941';
        pending uuid:='00000000-0000-4000-8000-000000008942';
        server uuid:='00000000-0000-4000-8000-000000008943';
        mass_id uuid:='00000000-0000-4000-8000-000000008944';
        unpublished uuid:='00000000-0000-4000-8000-000000008945';
        denied boolean;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM migration_private.environment WHERE id=true
    AND branch_id IN ('br-rough-hill-bcj6lzt1','br-odd-bread-bc1jxzsh'))
 THEN RAISE EXCEPTION 'Wrong branch'; END IF;
 BEGIN
  INSERT INTO public.profiles(id,name,email,role,approved) VALUES
    (parent,'Parent negative RLS','parent-rbac-rollback@example.invalid','pai',true),
    (pending,'Pending negative RLS','pending-rbac-rollback@example.invalid','coroinha',false),
    (server,'Approved server RLS','server-rbac-rollback@example.invalid','coroinha',true);
  INSERT INTO public.masses(id,title,starts_at,published) VALUES
    (mass_id,'Open mass RLS',now()+interval '3 days',true),
    (unpublished,'Unpublished RLS',now()+interval '3 days',false);
  -- A request now requires an actual open vacancy in the matching group.
  INSERT INTO public.assignments(mass_id,function_name,service_group) VALUES
    (mass_id,'RLS test vacancy','coroinha'),
    (unpublished,'RLS unpublished vacancy','coroinha');
  FOREACH parent IN ARRAY ARRAY[parent,pending] LOOP
   PERFORM set_config('app.user_id',parent::text,true);
   EXECUTE 'SET LOCAL ROLE coroinhas_app';
   denied:=false;
   BEGIN
    INSERT INTO public.requests(mass_id,user_id,type) VALUES(mass_id,parent,'servir');
   EXCEPTION WHEN insufficient_privilege THEN denied:=true;
   END;
   IF NOT denied THEN RAISE EXCEPTION 'Parent or pending user requested to serve';END IF;
   EXECUTE 'RESET ROLE';
  END LOOP;
  PERFORM set_config('app.user_id',server::text,true);
  EXECUTE 'SET LOCAL ROLE coroinhas_app';
  INSERT INTO public.requests(mass_id,user_id,type) VALUES(mass_id,server,'servir');
  denied:=false;
  BEGIN
   INSERT INTO public.requests(mass_id,user_id,type)
    VALUES(unpublished,server,'servir');
  EXCEPTION WHEN insufficient_privilege THEN denied:=true;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'Unpublished mass request permitted';END IF;
  IF EXISTS(SELECT 1 FROM public.profile_directory WHERE id=pending AND email IS NOT NULL)
  THEN RAISE EXCEPTION 'Private email exposed to another user';END IF;
  RAISE EXCEPTION 'ROLLBACK_ALL_FIXTURES';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'ROLLBACK_ALL_FIXTURES' THEN RAISE;END IF;
 END;
 IF EXISTS(SELECT 1 FROM public.profiles WHERE id=server)
 THEN RAISE EXCEPTION 'Fixture survived rollback';END IF;
END $test$;