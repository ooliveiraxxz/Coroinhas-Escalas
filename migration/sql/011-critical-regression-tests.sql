-- Staging-only SQL regression checks. This script always ends with ROLLBACK.
-- DO NOT run on Supabase or either production branch.
BEGIN;
DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM migration_private.environment WHERE branch_id='br-rough-hill-bcj6lzt1') THEN RAISE EXCEPTION 'Wrong branch'; END IF; END $$;
INSERT INTO public.profiles(id,name,email,role,approved) VALUES
 ('00000000-0000-4000-8000-000000006101','Approved test','approved.fixture@example.invalid','coroinha',true),
 ('00000000-0000-4000-8000-000000006102','Pending test','pending.fixture@example.invalid','coroinha',false);
INSERT INTO public.masses(id,title,starts_at,published) VALUES('00000000-0000-4000-8000-000000006201','Fixture future',now()+interval '3 days',true);
INSERT INTO public.assignments(id,mass_id,function_name,status)
 VALUES('00000000-0000-4000-8000-000000006301','00000000-0000-4000-8000-000000006201','Test','escalado');
INSERT INTO public.requests(id,mass_id,assignment_id,user_id,type)
 VALUES('00000000-0000-4000-8000-000000006401','00000000-0000-4000-8000-000000006201','00000000-0000-4000-8000-000000006301','00000000-0000-4000-8000-000000006101','substituir');
SELECT set_config('app.user_id',(SELECT id::text FROM public.profiles WHERE role='coordenadora' AND approved LIMIT 1),true);
SET LOCAL ROLE coroinhas_app;
DO $$ DECLARE denied boolean:=false; BEGIN
 BEGIN PERFORM public.approve_service_request('00000000-0000-4000-8000-000000006401','00000000-0000-4000-8000-000000006301');
 EXCEPTION WHEN OTHERS THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Stale vacancy was approved'; END IF;
END $$;
RESET ROLE;
UPDATE public.assignments SET status='desmarcado' WHERE id='00000000-0000-4000-8000-000000006301';
UPDATE public.requests SET user_id='00000000-0000-4000-8000-000000006102' WHERE id='00000000-0000-4000-8000-000000006401';
SET LOCAL ROLE coroinhas_app;
DO $$ DECLARE denied boolean:=false; BEGIN
 BEGIN PERFORM public.approve_service_request('00000000-0000-4000-8000-000000006401','00000000-0000-4000-8000-000000006301');
 EXCEPTION WHEN OTHERS THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Unapproved server assigned'; END IF;
END $$;
RESET ROLE;
UPDATE public.requests SET user_id='00000000-0000-4000-8000-000000006101' WHERE id='00000000-0000-4000-8000-000000006401';
SET LOCAL ROLE coroinhas_app;
SELECT public.approve_service_request('00000000-0000-4000-8000-000000006401','00000000-0000-4000-8000-000000006301');
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.assignments WHERE id='00000000-0000-4000-8000-000000006301' AND status='escalado' AND server_id='00000000-0000-4000-8000-000000006101') THEN RAISE EXCEPTION 'Valid request was rejected'; END IF;
END $$;
RESET ROLE;
SELECT set_config('app.user_id','00000000-0000-4000-8000-000000006101',true);
SET LOCAL ROLE coroinhas_app;
DO $$ BEGIN
 IF EXISTS (SELECT 1 FROM public.profile_directory WHERE id<>auth.uid() AND (email IS NOT NULL OR notes IS NOT NULL OR last_seen_at IS NOT NULL OR notification_preferences IS NOT NULL))
 THEN RAISE EXCEPTION 'Profile private columns exposed'; END IF;
END $$;
RESET ROLE;
ROLLBACK;
