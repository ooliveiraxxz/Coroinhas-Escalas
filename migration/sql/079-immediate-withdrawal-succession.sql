-- QA 079: Fill a withdrawn position from its existing pending request queue.
-- Candidates: same mass/group, approved, not the person withdrawing, and not already
-- assigned to this mass. Earlier request wins; request ID provides a stable tie-break.
-- Unlike the routine that initially assigns 3h before Mass, a withdrawal can
-- be handled immediately, even if the Mass is more than 3h away.
-- Does not create users or alter positions when no eligible request is found.
CREATE OR REPLACE FUNCTION public.auto_refill_withdrawn_assignment()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $function$
DECLARE
 v_candidate public.requests%ROWTYPE;
 v_starts_at timestamptz;
BEGIN
 IF NEW.status IS DISTINCT FROM 'desmarcado'
    OR OLD.status IS NOT DISTINCT FROM 'desmarcado'
    OR NEW.server_id IS NULL
    OR NOT EXISTS (
      SELECT 1 FROM public.service_settings
      WHERE key='auto_approval_3h' AND enabled
    ) THEN RETURN NEW; END IF;

 SELECT m.starts_at INTO v_starts_at
 FROM public.masses m
 WHERE m.id=NEW.mass_id AND m.published AND m.archived_at IS NULL;
 IF v_starts_at IS NULL OR v_starts_at<=now() THEN RETURN NEW; END IF;

 -- Serialize automatic succession for all slots of the same Mass.
 -- Existing unique partial index remains the final double-assignment safeguard.
 PERFORM pg_advisory_xact_lock(hashtextextended(NEW.mass_id::text,0));

 SELECT r.* INTO v_candidate
 FROM public.requests r
 JOIN public.profiles p ON p.id=r.user_id
 WHERE r.mass_id=NEW.mass_id AND r.status='pendente'
   AND r.service_group=NEW.service_group
   AND p.approved AND p.role=NEW.service_group
   AND r.user_id<>NEW.server_id
   AND ((r.type='substituir' AND r.assignment_id=NEW.id)
        OR (r.type='servir' AND r.assignment_id IS NULL))
   AND NOT EXISTS (
     SELECT 1 FROM public.assignments a
     WHERE a.mass_id=NEW.mass_id AND a.server_id=r.user_id
       AND a.status<>'desmarcado'
   )
 ORDER BY r.created_at,r.id
 LIMIT 1 FOR UPDATE OF r SKIP LOCKED;
 IF NOT FOUND THEN RETURN NEW; END IF;

 UPDATE public.assignments
 SET server_id=v_candidate.user_id,status='escalado',reason=NULL
 WHERE id=NEW.id AND status='desmarcado';
 IF FOUND THEN
   UPDATE public.requests SET status='aprovado'
   WHERE id=v_candidate.id AND status='pendente';
   INSERT INTO public.notifications(user_id,title,body,event_key)
   VALUES(v_candidate.user_id,'Você foi escalado automaticamente',
   'Você foi chamado para substituir em '||
   to_char(v_starts_at AT TIME ZONE 'America/Sao_Paulo',
     'DD/MM/YYYY HH24:MI')||' na função '||NEW.function_name||'.',
   'automatic_approval');
 END IF;
 RETURN NEW;
END $function$;

-- AFTER trigger avoids modifying the row in the BEFORE trigger chain.
-- Distinct name keeps the existing manual/automatic assignment notification trigger.
DROP TRIGGER IF EXISTS zz_auto_refill_withdrawn_assignment_trg ON public.assignments;
CREATE TRIGGER zz_auto_refill_withdrawn_assignment_trg
AFTER UPDATE OF status ON public.assignments
FOR EACH ROW WHEN (OLD.status IS DISTINCT FROM NEW.status AND NEW.status='desmarcado')
EXECUTE FUNCTION public.auto_refill_withdrawn_assignment();

REVOKE ALL ON FUNCTION public.auto_refill_withdrawn_assignment() FROM PUBLIC;
-- Trigger invocation does not require granting EXECUTE to application roles.
