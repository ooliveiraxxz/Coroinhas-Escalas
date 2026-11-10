-- Automação imediata para solicitações elegíveis nas últimas 3 horas.
-- A verificação na abertura da janela depende de agendador externo periódico.
CREATE OR REPLACE FUNCTION public.auto_approve_new_service_request()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
BEGIN
 IF NEW.status='pendente' AND (TG_OP='INSERT' OR OLD.status IS DISTINCT FROM NEW.status)
 AND EXISTS (
   SELECT 1 FROM public.masses m
   WHERE m.id=NEW.mass_id AND m.published
     AND m.starts_at>now()
     AND m.starts_at<=now()+INTERVAL '3 hours'
 ) THEN
  PERFORM public.run_pending_auto_approvals();
 END IF;
 RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS auto_approve_new_service_request_trg ON public.requests;
CREATE TRIGGER auto_approve_new_service_request_trg
AFTER INSERT OR UPDATE OF status ON public.requests
FOR EACH ROW EXECUTE FUNCTION public.auto_approve_new_service_request();

INSERT INTO public.service_settings(key,enabled,updated_at)
VALUES ('auto_approval_3h',true,now())
ON CONFLICT (key) DO UPDATE SET enabled=EXCLUDED.enabled,updated_at=EXCLUDED.updated_at;
