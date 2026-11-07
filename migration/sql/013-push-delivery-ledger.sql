-- Only br-rough-hill-bcj6lzt1; applied once. Manual/test subscriptions only.
DO $guard$ BEGIN IF NOT EXISTS(SELECT 1 FROM migration_private.environment WHERE branch_id='br-rough-hill-bcj6lzt1') THEN RAISE EXCEPTION 'Wrong branch';END IF; END $guard$;

CREATE TABLE migration_private.push_delivery_attempts (
notification_id uuid NOT NULL REFERENCES public.notifications(id) ON DELETE CASCADE,
subscription_id uuid NOT NULL REFERENCES public.push_subscriptions(id) ON DELETE CASCADE,
status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','sending','retry','sent','permanent_failure')),
attempts integer NOT NULL DEFAULT 0 CHECK (attempts>=0),
next_attempt_at timestamptz NOT NULL DEFAULT now(),
last_error_code integer,
last_error_at timestamptz,
updated_at timestamptz NOT NULL DEFAULT now(),
PRIMARY KEY(notification_id,subscription_id));

REVOKE ALL ON migration_private.push_delivery_attempts FROM PUBLIC,coroinhas_app,coroinhas_gateway;

CREATE INDEX push_delivery_pending_idx ON migration_private.push_delivery_attempts(status,next_attempt_at) WHERE status IN ('pending','retry','sending');
