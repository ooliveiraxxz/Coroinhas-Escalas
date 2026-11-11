-- Transactional simulation of Neon push delivery, deliberately rolled back.
-- This must leave no profiles, subscriptions, notifications or delivery attempts.
-- Run only in the authorized isolated Neon branch.
DO $t$
DECLARE p uuid:='00000000-0000-4000-8000-000000009812';
        s uuid:='00000000-0000-4000-8000-000000009811';
        k uuid:='00000000-0000-4000-8000-000000009810';
        matched integer; finished boolean;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM migration_private.environment
    WHERE branch_id='br-crimson-mud-bcyk3t3x')
 THEN RAISE EXCEPTION 'Wrong branch'; END IF;
 IF (SELECT enabled FROM migration_private.push_runtime WHERE id=true)
 THEN RAISE EXCEPTION 'Push must start disabled';END IF;
 BEGIN
  UPDATE migration_private.push_runtime SET enabled=true,activated_at=now()-interval '1 minute' WHERE id=true;
  INSERT INTO public.profiles(id,name,email,role,approved)
   VALUES(p,'Push transaction fixture','push-rollback-only@example.invalid','coroinha',true);
  INSERT INTO public.push_subscriptions(id,user_id,endpoint,p256dh,auth,created_at)
   VALUES(s,p,'https://push.invalid/subscription-only-in-rollback','dummy','dummy',now());
  INSERT INTO public.notifications(id,user_id,title,body,created_at)
   VALUES(k,p,'Teste de nova escala','Simulação revertida',now());
  IF (SELECT state FROM migration_private.push_outbox WHERE notification_id=k)<>'pending'
  THEN RAISE EXCEPTION 'Expected pending outbox row';END IF;
  SELECT count(*) INTO matched FROM migration_private.push_claim(10)
   WHERE notification_id=k AND subscription_id=s AND attempt_number=1;
  IF matched<>1 THEN RAISE EXCEPTION 'Claim did not select the new subscription';END IF;
  SELECT migration_private.push_finish(k,s,1,true,0) INTO finished;
  IF NOT finished THEN RAISE EXCEPTION 'Claim acknowledgement failed';END IF;
  IF (SELECT status FROM migration_private.push_delivery_attempts WHERE notification_id=k AND subscription_id=s)<>'sent'
  THEN RAISE EXCEPTION 'Expected sent ledger state';END IF;
  IF EXISTS(SELECT 1 FROM migration_private.push_claim(10) WHERE notification_id=k)
  THEN RAISE EXCEPTION 'Already sent item was claimed twice';END IF;
  RAISE EXCEPTION 'ROLLBACK_FIXTURE_SUCCESS';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'ROLLBACK_FIXTURE_SUCCESS' THEN RAISE;END IF;
 END;
 IF EXISTS(SELECT 1 FROM public.profiles WHERE id=p) OR
    EXISTS(SELECT 1 FROM migration_private.push_delivery_attempts WHERE notification_id=k)
 THEN RAISE EXCEPTION 'Fixture was not rolled back';END IF;
 IF (SELECT enabled FROM migration_private.push_runtime WHERE id=true)
 THEN RAISE EXCEPTION 'Runtime enabled after test';END IF;
END $t$;
