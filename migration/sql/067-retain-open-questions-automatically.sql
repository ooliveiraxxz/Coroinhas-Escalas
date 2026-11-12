-- Apply normal 30 + 30-day retention to open-text questions; answers cascade on purge.
CREATE OR REPLACE FUNCTION public.archive_maintenance()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE result jsonb := '{}'::jsonb; n integer;
BEGIN
 IF NOT public.automation_enabled('archive_retention') THEN
  RETURN jsonb_build_object('enabled',false,'status','disabled');
 END IF;
 -- Only one maintenance run at a time, even if both Vercel Cron and a live client call.
 IF NOT pg_try_advisory_xact_lock(937144001) THEN
  RETURN jsonb_build_object('enabled',true,'status','already_running');
 END IF;
 -- A mass is archived 24 hours after its actual scheduled start time.
 UPDATE public.masses SET archived_at=now()
 WHERE archived_at IS NULL AND starts_at <= now()-interval '24 hours';
 GET DIAGNOSTICS n=ROW_COUNT;
 result:=result||jsonb_build_object('masses_archived',n);
 UPDATE public.notifications SET archived_at=now()
 WHERE archived_at IS NULL AND created_at<=now()-interval '30 days';
 GET DIAGNOSTICS n=ROW_COUNT;
 result:=result||jsonb_build_object('notifications_archived',n);
 -- Keep poll available while open; start counting after closing.
 UPDATE public.polls SET archived_at=now()
 WHERE archived_at IS NULL AND ends_at<=now()-interval '30 days';
 GET DIAGNOSTICS n=ROW_COUNT;
 result:=result||jsonb_build_object('polls_archived',n);
 UPDATE public.screen_announcements SET archived_at=now(),active=false
 WHERE archived_at IS NULL AND created_at<=now()-interval '30 days';
 GET DIAGNOSTICS n=ROW_COUNT;
 result:=result||jsonb_build_object('announcements_archived',n);
 UPDATE public.messages SET archived_at=now()
 WHERE archived_at IS NULL AND created_at<=now()-interval '30 days';
 GET DIAGNOSTICS n=ROW_COUNT;
 result:=result||jsonb_build_object('messages_archived',n);
 -- Never delete an open support conversation; start retention after closure.
 UPDATE public.support_tickets SET archived_at=now()
 WHERE archived_at IS NULL AND status='encerrado'
 AND coalesce(closed_at,updated_at,created_at)<=now()-interval '30 days';
 GET DIAGNOSTICS n=ROW_COUNT;
 result:=result||jsonb_build_object('support_archived',n);

 -- Keep answered questions available for 30 days after the deadline before archive.
 UPDATE public.open_questions SET archived_at=now()
 WHERE archived_at IS NULL AND ends_at<=now()-interval '30 days';
 GET DIAGNOSTICS n=ROW_COUNT;
 result:=result||jsonb_build_object('questions_archived',n);
  -- Retain archived records for another 30 full days.
 DELETE FROM public.notifications WHERE archived_at<=now()-interval '30 days';
 GET DIAGNOSTICS n=ROW_COUNT;
 result:=result||jsonb_build_object('notifications_removed',n);
 DELETE FROM public.messages WHERE archived_at<=now()-interval '30 days';
 GET DIAGNOSTICS n=ROW_COUNT;
 result:=result||jsonb_build_object('messages_removed',n);
 DELETE FROM public.screen_announcements WHERE archived_at<=now()-interval '30 days';
 GET DIAGNOSTICS n=ROW_COUNT;
 result:=result||jsonb_build_object('announcements_removed',n);
 DELETE FROM public.open_questions WHERE archived_at<=now()-interval '30 days';
 GET DIAGNOSTICS n=ROW_COUNT;
 result:=result||jsonb_build_object('questions_removed',n);
  DELETE FROM public.polls WHERE archived_at<=now()-interval '30 days';
 GET DIAGNOSTICS n=ROW_COUNT;
 result:=result||jsonb_build_object('polls_removed',n);
 DELETE FROM public.support_tickets WHERE archived_at<=now()-interval '30 days';
 GET DIAGNOSTICS n=ROW_COUNT;
 result:=result||jsonb_build_object('support_removed',n);
 DELETE FROM public.masses WHERE archived_at<=now()-interval '30 days';
 GET DIAGNOSTICS n=ROW_COUNT;
 result:=result||jsonb_build_object('masses_removed',n);
 RETURN result||jsonb_build_object('enabled',true,'status','ok');
END $function$
;
