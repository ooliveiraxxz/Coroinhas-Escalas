-- Somente para revisao/homologacao. NAO executar em producao sem aprovacao especifica.
-- Consolida filas sem alterar public.notifications e sem reenviar avisos antigos.
CREATE OR REPLACE FUNCTION migration_private.push_finalize_outbox(p_limit integer DEFAULT 100)
RETURNS TABLE(sent_count integer, failed_count integer, suppressed_count integer)
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
BEGIN
 IF p_limit IS NULL OR p_limit < 1 OR p_limit > 500 THEN
  RAISE EXCEPTION 'Invalid batch size' USING ERRCODE='22023';
 END IF;
 RETURN QUERY
 WITH candidates AS (
  SELECT o.notification_id
  FROM migration_private.push_outbox o
  JOIN public.notifications n ON n.id=o.notification_id
  WHERE o.state='pending'
   AND (
    -- Sem assinatura no momento: nao ha destinatario push.
    NOT EXISTS (
      SELECT 1 FROM public.push_subscriptions s WHERE s.user_id=n.user_id
    )
    OR
    -- Assinaturas existentes: pelo menos um processamento conhecido e
    -- nenhuma assinatura sem resultado final.
    (
      EXISTS (
       SELECT 1 FROM migration_private.push_delivery_attempts a
       WHERE a.notification_id=o.notification_id
      )
      AND NOT EXISTS (
       SELECT 1 FROM public.push_subscriptions s
       LEFT JOIN migration_private.push_delivery_attempts a
        ON a.notification_id=o.notification_id AND a.subscription_id=s.id
       WHERE s.user_id=n.user_id
        AND (a.status IS NULL OR a.status NOT IN ('sent','permanent_failure'))
      )
    )
   )
  ORDER BY o.created_at
  LIMIT p_limit
  FOR UPDATE OF o SKIP LOCKED
 ),
 changed AS (
  UPDATE migration_private.push_outbox o
  SET state=CASE
   WHEN EXISTS (SELECT 1 FROM migration_private.push_delivery_attempts a
                WHERE a.notification_id=o.notification_id AND a.status='sent') THEN 'sent'
   WHEN EXISTS (SELECT 1 FROM public.notifications n
                JOIN public.push_subscriptions s ON s.user_id=n.user_id
                WHERE n.id=o.notification_id) THEN 'failed'
   ELSE 'suppressed'
  END
  FROM candidates c
  WHERE o.notification_id=c.notification_id AND o.state='pending'
  RETURNING o.state
 )
 SELECT count(*) FILTER (WHERE state='sent')::integer,
        count(*) FILTER (WHERE state='failed')::integer,
        count(*) FILTER (WHERE state='suppressed')::integer
 FROM changed;
END
$function$;
REVOKE ALL ON FUNCTION migration_private.push_finalize_outbox(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION migration_private.push_finalize_outbox(integer) TO coroinhas_push_worker;
