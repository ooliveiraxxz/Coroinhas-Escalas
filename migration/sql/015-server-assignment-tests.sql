-- Run ONLY on isolated staging; every fixture rolls back.
BEGIN;
INSERT INTO public.profiles(id,name,email,role,approved) VALUES ('00000000-0000-4000-8000-000000008101','Fixture parent','parent.guard@example.invalid','pai',true),('00000000-0000-4000-8000-000000008102','Fixture server','server.guard@example.invalid','coroinha',true),('00000000-0000-4000-8000-000000008103','Fixture pending','pending.guard@example.invalid','coroinha',false);
INSERT INTO public.masses(id,title,starts_at,published) VALUES('00000000-0000-4000-8000-000000008201','Fixture guard',now()+interval '1 day',true);
DO $$ DECLARE u uuid; BEGIN FOREACH u IN ARRAY ARRAY['00000000-0000-4000-8000-000000008101'::uuid,'00000000-0000-4000-8000-000000008103'::uuid] LOOP
 BEGIN INSERT INTO public.assignments(mass_id,function_name,server_id) VALUES('00000000-0000-4000-8000-000000008201','Fixture',u); RAISE EXCEPTION 'Forbidden server accepted' USING ERRCODE='XX000'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN INSERT INTO public.fixed_rules(server_id,function_name,weekday,hour,minute,location) VALUES(u,'Fixture',0,10,0,'Fixture'); RAISE EXCEPTION 'Forbidden fixed server accepted' USING ERRCODE='XX000'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 END LOOP; END $$;
INSERT INTO public.assignments(id,mass_id,function_name,server_id) VALUES('00000000-0000-4000-8000-000000008301','00000000-0000-4000-8000-000000008201','Fixture','00000000-0000-4000-8000-000000008102');
DO $$ BEGIN BEGIN UPDATE public.assignments SET server_id='00000000-0000-4000-8000-000000008101' WHERE id='00000000-0000-4000-8000-000000008301'; RAISE EXCEPTION 'Parent reassignment accepted' USING ERRCODE='XX000'; EXCEPTION WHEN insufficient_privilege THEN NULL; END; END $$;
UPDATE public.assignments SET status='presente' WHERE id='00000000-0000-4000-8000-000000008301';
DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM public.assignments WHERE id='00000000-0000-4000-8000-000000008301' AND status='presente') THEN RAISE EXCEPTION 'Presence regression'; END IF; END $$;
ROLLBACK;
