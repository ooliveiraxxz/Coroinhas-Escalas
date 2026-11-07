-- Somente homologação. Todas as fixtures são revertidas.
BEGIN;
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM migration_private.environment WHERE branch_id='br-rough-hill-bcj6lzt1') THEN RAISE EXCEPTION 'Branch incorreta'; END IF;
END $$;
INSERT INTO public.profiles(id,name,email,role,approved) VALUES
 ('00000000-0000-4000-8000-000000008101','Request parent','request-parent.fixture@example.invalid','pai',true),
 ('00000000-0000-4000-8000-000000008102','Request pending','request-pending.fixture@example.invalid','coroinha',false),
 ('00000000-0000-4000-8000-000000008103','Request approved','request-approved.fixture@example.invalid','coroinha',true);
INSERT INTO public.masses(id,title,starts_at,published) VALUES
 ('00000000-0000-4000-8000-000000008201','Request policy fixture',now()+interval '3 days',true);
SET LOCAL ROLE coroinhas_app;
DO $$
DECLARE uid text;
BEGIN
 FOREACH uid IN ARRAY ARRAY['00000000-0000-4000-8000-000000008101','00000000-0000-4000-8000-000000008102'] LOOP
  PERFORM set_config('app.user_id',uid,true);
  BEGIN
   INSERT INTO public.requests(mass_id,user_id,type) VALUES('00000000-0000-4000-8000-000000008201',uid::uuid,'servir');
   RAISE EXCEPTION 'Parent or pending profile was allowed' USING ERRCODE='XX000';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
 END LOOP;
 PERFORM set_config('app.user_id','00000000-0000-4000-8000-000000008103',true);
 INSERT INTO public.requests(mass_id,user_id,type) VALUES('00000000-0000-4000-8000-000000008201',auth.uid(),'servir');
 IF NOT EXISTS(SELECT 1 FROM public.requests WHERE mass_id='00000000-0000-4000-8000-000000008201' AND user_id=auth.uid()) THEN
  RAISE EXCEPTION 'Approved server request missing';
 END IF;
 BEGIN
  INSERT INTO public.requests(mass_id,user_id,type) VALUES('00000000-0000-4000-8000-000000008201','00000000-0000-4000-8000-000000008101','servir');
  RAISE EXCEPTION 'Request for another user allowed' USING ERRCODE='XX000';
 EXCEPTION WHEN insufficient_privilege THEN NULL;
 END;
END $$;
RESET ROLE;
ROLLBACK;
