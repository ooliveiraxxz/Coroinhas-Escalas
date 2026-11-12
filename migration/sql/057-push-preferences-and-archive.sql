-- Applied only to isolated homologation; production rollout remains pending.
-- Preserve existing activation, ownership, ban and age guards.
CREATE OR REPLACE FUNCTION migration_private.push_eligible(p_notice uuid, p_subscription uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 SELECT EXISTS(
  SELECT 1 FROM migration_private.push_runtime config
  JOIN migration_private.push_outbox o ON o.state='pending'
  JOIN public.notifications n ON n.id=o.notification_id
  JOIN public.profiles p ON p.id=n.user_id
  JOIN public.push_subscriptions s ON s.user_id=p.id
  WHERE config.id AND config.enabled AND config.activated_at IS NOT NULL
   AND n.id=p_notice AND s.id=p_subscription
   AND n.archived_at IS NULL
   AND coalesce(p.notification_preferences->>n.event_key,'true')<>'false'
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
$function$
