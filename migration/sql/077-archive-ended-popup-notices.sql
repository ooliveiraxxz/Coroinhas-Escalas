-- Pop-up notices can be archived only after the publisher deactivates them.
CREATE OR REPLACE FUNCTION public.archive_screen_announcement(p_id uuid) RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $fn$
DECLARE v_count int;
BEGIN
 IF NOT public.has_site_permission('send_popup') THEN RAISE EXCEPTION 'Sem permissão' USING ERRCODE='42501'; END IF;
 IF EXISTS(SELECT 1 FROM public.screen_announcements WHERE id=p_id AND active AND archived_at IS NULL AND (created_by=auth.uid() OR public.is_developer())) THEN
  RAISE EXCEPTION 'Desative o aviso antes de apagá-lo' USING ERRCODE='22023';
 END IF;
 UPDATE public.screen_announcements SET archived_at=now() WHERE id=p_id AND active=false AND archived_at IS NULL AND (created_by=auth.uid() OR public.is_developer());
 GET DIAGNOSTICS v_count=ROW_COUNT;RETURN v_count=1;
END $fn$;

REVOKE ALL ON FUNCTION public.archive_screen_announcement(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.archive_screen_announcement(uuid) TO coroinhas_app;
