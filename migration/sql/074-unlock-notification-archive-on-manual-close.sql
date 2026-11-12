-- On manual close, release trash action immediately without waiting for original deadline.
CREATE OR REPLACE FUNCTION public.open_question_close(p_question uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE n integer;BEGIN
 IF NOT public.has_site_permission('manage_polls') THEN RAISE EXCEPTION 'Sem permissão' USING ERRCODE='42501'; END IF;
 UPDATE public.open_questions SET ends_at=now() WHERE id=p_question AND ends_at>now() AND archived_at IS NULL AND (created_by=auth.uid() OR public.is_developer());
 GET DIAGNOSTICS n=ROW_COUNT;
 IF n=1 THEN
  UPDATE public.notifications SET priority_until=now() WHERE group_id=p_question
    AND event_key='open_questions' AND priority_until>now() AND archived_at IS NULL;
 END IF;
 RETURN n=1;
END $function$
;

CREATE OR REPLACE FUNCTION public.poll_close(p_poll uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE n integer;BEGIN
 IF NOT public.has_site_permission('manage_polls') THEN RAISE EXCEPTION 'Sem permissão' USING ERRCODE='42501'; END IF;
 UPDATE public.polls SET closed_at=now() WHERE id=p_poll AND ends_at>now() AND closed_at IS NULL AND archived_at IS NULL AND (created_by=auth.uid() OR public.is_developer());
 GET DIAGNOSTICS n=ROW_COUNT;
 IF n=1 THEN
  UPDATE public.notifications SET priority_until=now() WHERE group_id=p_poll
    AND event_key='polls' AND priority_until>now() AND archived_at IS NULL;
 END IF;
 RETURN n=1;
END $function$
;
