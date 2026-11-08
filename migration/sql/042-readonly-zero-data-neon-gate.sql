-- Read-only clean Neon readiness gate, before first genuine account signup.
-- Run on br-rough-hill-bcj6lzt1; fails closed on any residual record or policy loss.
WITH app_rows AS (
 SELECT
 (SELECT count(*) FROM public.profiles)
 +(SELECT count(*) FROM public.assignments)
 +(SELECT count(*) FROM public.masses)
 +(SELECT count(*) FROM public.requests)
 +(SELECT count(*) FROM public.notifications)
 +(SELECT count(*) FROM public.messages)
 +(SELECT count(*) FROM public.guides)
 +(SELECT count(*) FROM public.fixed_rules)
 +(SELECT count(*) FROM public.site_updates)
 +(SELECT count(*) FROM public.audit_log)
 +(SELECT count(*) FROM public.banned_emails)
 +(SELECT count(*) FROM public.login_events)
 +(SELECT count(*) FROM public.push_subscriptions)
 +(SELECT count(*) FROM public.screen_announcements)
 +(SELECT count(*) FROM public.screen_announcement_dismissals) AS total
)
SELECT
 (SELECT branch_id FROM migration_private.environment WHERE id=true) AS target_branch,
 (SELECT total FROM app_rows)::int AS app_rows,
 (SELECT count(*) FROM neon_auth."user")::int AS auth_users,
 (SELECT count(*) FROM migration_private.identity_map)::int AS identity_links,
 (SELECT count(*) FROM migration_private.push_outbox)::int AS push_outbox,
 (SELECT count(*) FROM migration_private.push_delivery_attempts)::int AS push_attempts,
 (SELECT count(*) FROM pg_policies WHERE schemaname='public')::int AS public_policies,
 (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='public' AND c.relkind='r' AND NOT c.relrowsecurity)::int AS tables_without_rls,
 (SELECT enabled FROM migration_private.push_runtime WHERE id=true) AS push_enabled,
 (SELECT count(*) FROM migration_private.cutover_reset_archive_20261108)::int AS archived_tables,
 (
  (SELECT branch_id FROM migration_private.environment WHERE id=true)='br-rough-hill-bcj6lzt1'
  AND (SELECT total FROM app_rows)=0
  AND (SELECT count(*) FROM neon_auth."user")=0
  AND (SELECT count(*) FROM migration_private.identity_map)=0
  AND (SELECT count(*) FROM migration_private.push_outbox)=0
  AND (SELECT count(*) FROM migration_private.push_delivery_attempts)=0
  AND (SELECT count(*) FROM pg_policies WHERE schemaname='public')=33
  AND (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
       WHERE n.nspname='public' AND c.relkind='r' AND NOT c.relrowsecurity)=0
  AND (SELECT enabled FROM migration_private.push_runtime WHERE id=true) IS FALSE
  AND (SELECT count(*) FROM migration_private.cutover_reset_archive_20261108)=16
 ) AS clean_stage_pass;