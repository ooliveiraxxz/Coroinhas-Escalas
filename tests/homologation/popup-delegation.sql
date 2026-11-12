-- Both checks passed. Changes roll back inside exception blocks.
DO $qa$ DECLARE rid uuid; denied boolean:=false; BEGIN
IF NOT EXISTS(SELECT 1 FROM migration_private.environment WHERE branch_id='br-crimson-mud-bcyk3t3x') THEN RAISE EXCEPTION 'isolated only'; END IF;
BEGIN
PERFORM set_config('app.user_id','00000000-0000-4000-8000-000000000001',true);
SET LOCAL ROLE coroinhas_app;
PERFORM public.developer_apply_permissions('00000000-0000-4000-8000-000000000002','[{"key":"send_popup","allowed":false}]',NULL,'DESENVOLVEDOR');
PERFORM set_config('app.user_id','00000000-0000-4000-8000-000000000002',true);
BEGIN
INSERT INTO public.screen_announcements(title,body,created_by) VALUES('QA delegated popup','QA isolated','00000000-0000-4000-8000-000000000002') RETURNING id INTO rid;
EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
IF denied IS DISTINCT FROM true THEN RAISE EXCEPTION 'permission mismatch'; END IF;
RAISE EXCEPTION 'QA_ROLLBACK_OK';
EXCEPTION WHEN OTHERS THEN
IF SQLERRM<>'QA_ROLLBACK_OK' THEN RAISE; END IF;
END;
END $qa$;
DO $qa$ DECLARE rid uuid; denied boolean:=false; BEGIN
IF NOT EXISTS(SELECT 1 FROM migration_private.environment WHERE branch_id='br-crimson-mud-bcyk3t3x') THEN RAISE EXCEPTION 'isolated only'; END IF;
BEGIN
PERFORM set_config('app.user_id','00000000-0000-4000-8000-000000000001',true);
SET LOCAL ROLE coroinhas_app;
PERFORM public.developer_apply_permissions('00000000-0000-4000-8000-000000000002','[{"key":"send_popup","allowed":true}]',NULL,'DESENVOLVEDOR');
PERFORM set_config('app.user_id','00000000-0000-4000-8000-000000000002',true);
BEGIN
INSERT INTO public.screen_announcements(title,body,created_by) VALUES('QA delegated popup','QA isolated','00000000-0000-4000-8000-000000000002') RETURNING id INTO rid;
EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
IF denied IS DISTINCT FROM false THEN RAISE EXCEPTION 'permission mismatch'; END IF;
RAISE EXCEPTION 'QA_ROLLBACK_OK';
EXCEPTION WHEN OTHERS THEN
IF SQLERRM<>'QA_ROLLBACK_OK' THEN RAISE; END IF;
END;
END $qa$;
