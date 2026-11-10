BEGIN;
CREATE TEMP TABLE qa_archive_check(result jsonb);
DO $qa$ DECLARE out jsonb; results jsonb; BEGIN
IF NOT EXISTS(SELECT 1 FROM migration_private.environment WHERE branch_id='br-crimson-mud-bcyk3t3x') THEN RAISE EXCEPTION 'Isolated branch required'; END IF;
BEGIN
PERFORM set_config('app.user_id','00000000-0000-4000-8000-000000000001',true);
PERFORM public.developer_apply_permissions('00000000-0000-4000-8000-000000000002','[{"key":"view_archives","allowed":true}]',NULL,'DESENVOLVEDOR');
PERFORM public.developer_apply_permissions('00000000-0000-4000-8000-000000000003','[{"key":"view_archives","allowed":true}]',NULL,'DESENVOLVEDOR');
INSERT INTO public.screen_announcements(title,body,target_role,target_user_id,created_by,archived_at) VALUES('Private QA popup','Private test body','individual','00000000-0000-4000-8000-000000000003','00000000-0000-4000-8000-000000000001',now());
PERFORM set_config('app.user_id','00000000-0000-4000-8000-000000000002',true);
SET LOCAL ROLE coroinhas_app;
out:=public.archive_list();
results:=jsonb_build_array(jsonb_build_object('name','archives/private-popup-other-user-blocked','passed',jsonb_array_length(out->'announcements')=0));
PERFORM set_config('app.user_id','00000000-0000-4000-8000-000000000003',true);
out:=public.archive_list();
results:=results||jsonb_build_array(jsonb_build_object('name','archives/private-popup-recipient-allowed','passed',jsonb_array_length(out->'announcements')=1));
PERFORM set_config('app.user_id','00000000-0000-4000-8000-000000000001',true);
out:=public.archive_list();
results:=results||jsonb_build_array(jsonb_build_object('name','archives/private-popup-developer-allowed','passed',jsonb_array_length(out->'announcements')=1));
RAISE EXCEPTION 'QA_ROLLBACK';
EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'QA_ROLLBACK' THEN RAISE; END IF; END;
INSERT INTO qa_archive_check VALUES(results);
END $qa$;
SELECT result FROM qa_archive_check;
ROLLBACK;

