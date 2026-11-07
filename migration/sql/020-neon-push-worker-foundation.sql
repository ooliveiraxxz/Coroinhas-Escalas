-- Neon push delivery foundation. Apply ONLY to isolated branch after review.
-- Every queue item remains suppressed until an explicit production cutover.
-- This migration NEVER sends notifications and NEVER enables the dispatcher.
DO $guard$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM migration_private.environment
               WHERE branch_id='br-rough-hill-bcj6lzt1')
 THEN RAISE EXCEPTION 'Wrong branch' USING ERRCODE='42501'; END IF;
END $guard$;

CREATE TABLE IF NOT EXISTS migration_private.push_runtime (
 id boolean PRIMARY KEY DEFAULT true CHECK (id),
 enabled boolean NOT NULL DEFAULT false,
 activated_at timestamptz,
 CHECK (NOT enabled OR activated_at IS NOT NULL)
);
INSERT INTO migration_private.push_runtime(id,enabled) VALUES(true,false)
ON CONFLICT (id) DO NOTHING;
REVOKE ALL ON migration_private.push_runtime FROM PUBLIC,coroinhas_gateway,coroinhas_app;

DO $role$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='coroinhas_push_worker') THEN
  CREATE ROLE coroinhas_push_worker NOLOGIN NOSUPERUSER NOCREATEDB
    NOCREATEROLE NOREPLICATION NOBYPASSRLS;
 END IF;
END $role$;
GRANT USAGE ON SCHEMA migration_private TO coroinhas_push_worker;
REVOKE ALL ON migration_private.push_runtime FROM coroinhas_push_worker;
REVOKE ALL ON migration_private.push_outbox FROM coroinhas_push_worker;
REVOKE ALL ON migration_private.push_delivery_attempts FROM coroinhas_push_worker;

CREATE OR REPLACE FUNCTION migration_private.push_eligible(p_notice uuid,p_subscription uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT EXISTS(
  SELECT 1 FROM migration_private.push_runtime config
  JOIN migration_private.push_outbox o ON o.state='pending'
  JOIN public.notifications n ON n.id=o.notification_id
  JOIN public.profiles p ON p.id=n.user_id
  JOIN public.push_subscriptions s ON s.user_id=p.id
  WHERE config.id AND config.enabled AND config.activated_at IS NOT NULL
   AND n.id=p_notice AND s.id=p_subscription
   AND n.created_at>=config.activated_at
   AND n.created_at>=now()-interval '24 hours'
   AND s.created_at>=config.activated_at
   AND p.approved
   AND NOT EXISTS(SELECT 1 FROM public.banned_emails b WHERE lower(b.email)=lower(p.email))
   AND coalesce(p.notification_preferences->>'enabled','true')<>'false'
   AND (n.title !~* 'vaga|substitui' OR coalesce(p.notification_preferences->>'free_slots','true')<>'false')
   AND (n.title !~* 'desmarc|desist' OR coalesce(p.notification_preferences->>'withdrawals','true')<>'false')
   AND (n.title !~* 'escala cadastrada|nova escala|você está escalado|escala atualizada'
        OR coalesce(p.notification_preferences->>'new_schedules','true')<>'false')
 );
$fn$;

CREATE OR REPLACE FUNCTION migration_private.push_claim(p_limit integer DEFAULT 10)
RETURNS TABLE(notification_id uuid,subscription_id uuid,endpoint text,p256dh text,
 auth text,title text,body text,attempt_number integer)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE candidate record; claimed integer;
BEGIN
 IF p_limit IS NULL OR p_limit<1 OR p_limit>20
 THEN RAISE EXCEPTION 'Invalid batch size' USING ERRCODE='22023';END IF;
 IF NOT EXISTS(SELECT 1 FROM migration_private.push_runtime
               WHERE id AND enabled AND activated_at IS NOT NULL) THEN RETURN; END IF;
 FOR candidate IN
  SELECT o.notification_id AS nid,s.id AS sid,s.endpoint,s.p256dh,s.auth,
         n.title,n.body
  FROM migration_private.push_outbox o
  JOIN public.notifications n ON n.id=o.notification_id
  JOIN public.push_subscriptions s ON s.user_id=n.user_id
  LEFT JOIN migration_private.push_delivery_attempts a
    ON a.notification_id=o.notification_id AND a.subscription_id=s.id
  WHERE o.state='pending'
    AND migration_private.push_eligible(o.notification_id,s.id)
    AND (a.notification_id IS NULL OR
      (a.attempts<4 AND
       ((a.status='retry' AND a.next_attempt_at<=now()) OR
        (a.status='sending' AND a.updated_at<now()-interval '15 minutes') OR
        a.status='pending')))
  ORDER BY o.created_at ASC
  LIMIT p_limit
  FOR UPDATE OF o SKIP LOCKED
 LOOP
  INSERT INTO migration_private.push_delivery_attempts(notification_id,subscription_id)
  VALUES(candidate.nid,candidate.sid) ON CONFLICT DO NOTHING;
  claimed:=NULL;
  UPDATE migration_private.push_delivery_attempts a
  SET status='sending',attempts=a.attempts+1,updated_at=now(),
      next_attempt_at=now()+interval '15 minutes'
  WHERE a.notification_id=candidate.nid AND a.subscription_id=candidate.sid
    AND a.attempts<4 AND
    (a.status='pending' OR (a.status='retry' AND a.next_attempt_at<=now())
      OR (a.status='sending' AND a.updated_at<now()-interval '15 minutes'))
  RETURNING a.attempts INTO claimed;
  IF claimed IS NOT NULL THEN
   notification_id:=candidate.nid;subscription_id:=candidate.sid;
   endpoint:=candidate.endpoint;p256dh:=candidate.p256dh;auth:=candidate.auth;
   title:=candidate.title;body:=candidate.body;attempt_number:=claimed;
   RETURN NEXT;
  END IF;
 END LOOP;
END $fn$;

CREATE OR REPLACE FUNCTION migration_private.push_finish(
 p_notification_id uuid,p_subscription_id uuid,p_attempt integer,
 p_success boolean,p_http_status integer DEFAULT 0)
RETURNS boolean LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE updated integer;
BEGIN
 IF p_attempt<1 OR p_attempt>4 OR p_success IS NULL OR
    p_http_status IS NULL OR p_http_status<0 OR p_http_status>599
 THEN RAISE EXCEPTION 'Invalid delivery outcome' USING ERRCODE='22023'; END IF;
 UPDATE migration_private.push_delivery_attempts d
 SET status=CASE WHEN p_success THEN 'sent'
           WHEN p_http_status IN (404,410) OR d.attempts>=4 THEN 'permanent_failure'
           ELSE 'retry' END,
     last_error_code=CASE WHEN p_success THEN NULL ELSE p_http_status END,
     last_error_at=CASE WHEN p_success THEN d.last_error_at ELSE now() END,
     next_attempt_at=CASE WHEN p_success THEN d.next_attempt_at
        ELSE now()+make_interval(mins=>least(60,power(2,d.attempts)::int)) END,
     updated_at=now()
 WHERE d.notification_id=p_notification_id AND d.subscription_id=p_subscription_id
   AND d.status='sending' AND d.attempts=p_attempt;
 GET DIAGNOSTICS updated=ROW_COUNT;
 RETURN updated=1;
END $fn$;

-- New notices are queued only after the cutover operator explicitly activates push.
-- Existing suppressed entries are never retroactively enqueued.
CREATE OR REPLACE FUNCTION migration_private.queue_push_notice()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE active boolean;
BEGIN
 SELECT enabled AND activated_at IS NOT NULL AND
        NEW.created_at>=activated_at INTO active
 FROM migration_private.push_runtime WHERE id;
 INSERT INTO migration_private.push_outbox(notification_id,state)
 VALUES(NEW.id,CASE WHEN coalesce(active,false) THEN 'pending' ELSE 'suppressed' END)
 ON CONFLICT DO NOTHING;
 RETURN NEW;
END $fn$;

REVOKE ALL ON FUNCTION migration_private.push_eligible(uuid,uuid) FROM PUBLIC,coroinhas_app,coroinhas_gateway;
REVOKE ALL ON FUNCTION migration_private.push_claim(integer) FROM PUBLIC,coroinhas_app,coroinhas_gateway;
REVOKE ALL ON FUNCTION migration_private.push_finish(uuid,uuid,integer,boolean,integer)
 FROM PUBLIC,coroinhas_app,coroinhas_gateway;
GRANT EXECUTE ON FUNCTION migration_private.push_eligible(uuid,uuid) TO coroinhas_push_worker;
GRANT EXECUTE ON FUNCTION migration_private.push_claim(integer) TO coroinhas_push_worker;
GRANT EXECUTE ON FUNCTION migration_private.push_finish(uuid,uuid,integer,boolean,integer)
 TO coroinhas_push_worker;
