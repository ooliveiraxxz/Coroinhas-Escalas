-- Read-only guardrail checks after applying 024 and 025 on Neon staging or clean rehearsal.
DO $assert$ DECLARE pol text;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM migration_private.environment WHERE id=true
  AND branch_id IN('br-rough-hill-bcj6lzt1','br-odd-bread-bc1jxzsh'))
 THEN RAISE EXCEPTION 'Wrong branch' USING ERRCODE='42501'; END IF;
 IF NOT has_column_privilege('coroinhas_app','public.profiles','name','UPDATE')
 OR NOT has_column_privilege('coroinhas_app','public.profiles','approved','UPDATE')
 OR NOT has_column_privilege('coroinhas_app','public.profiles','notification_preferences','UPDATE')
 OR has_column_privilege('coroinhas_app','public.profiles','role','UPDATE')
 OR has_column_privilege('coroinhas_app','public.profiles','email','UPDATE')
 OR has_column_privilege('coroinhas_app','public.profiles','created_at','UPDATE')
 OR has_column_privilege('coroinhas_app','public.profiles','last_seen_at','UPDATE')
 THEN RAISE EXCEPTION 'Unexpected profile write permissions'; END IF;
 SELECT with_check INTO pol FROM pg_policies WHERE schemaname='public'
  AND tablename='requests' AND policyname='requests_insert';
 IF pol IS NULL OR pol NOT LIKE '%published%' OR pol NOT LIKE '%starts_at%'
  OR pol NOT LIKE '%assignment_id%' OR pol NOT LIKE '%desmarcado%'
  OR pol NOT LIKE '%is_approved%'
 THEN RAISE EXCEPTION 'Requests insert policy is incomplete'; END IF;
 IF (SELECT count(*) FROM pg_policies WHERE schemaname='public')<>33
 THEN RAISE EXCEPTION 'Policy count drift'; END IF;
 IF EXISTS(SELECT 1 FROM pg_tables WHERE schemaname='public' AND NOT rowsecurity)
 THEN RAISE EXCEPTION 'Public table without RLS'; END IF;
END $assert$;
