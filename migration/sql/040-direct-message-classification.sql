-- 2026-11-09: distinguir mensagens individuais de avisos gerais na central dos coroinhas.
-- Executado no Neon em 2026-11-09. Idempotente para recuperações do banco.
CREATE OR REPLACE FUNCTION public.send_notification_targeted(
 p_title text, p_body text, p_target text, p_recipient uuid DEFAULT NULL::uuid
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
 v_group uuid := gen_random_uuid();
 v_count integer;
BEGIN
 IF NOT public.is_coordinator() THEN RAISE EXCEPTION 'Acesso negado' USING ERRCODE='42501'; END IF;
 IF length(trim(coalesce(p_title,'')))=0 OR length(trim(coalesce(p_body,'')))=0 THEN
  RAISE EXCEPTION 'Informe título e mensagem' USING ERRCODE='22023';
 END IF;
 IF p_target NOT IN ('coroinha','pai','coordenadora','todos','individual') OR p_target IS NULL THEN
  RAISE EXCEPTION 'Destinatário inválido' USING ERRCODE='22023';
 END IF;
 IF (p_target='individual' AND p_recipient IS NULL) OR (p_target<>'individual' AND p_recipient IS NOT NULL) THEN
  RAISE EXCEPTION 'Seleção de destinatários inválida' USING ERRCODE='22023';
 END IF;
 INSERT INTO public.notifications(user_id,title,body,group_id,seen,read_at,event_key)
 SELECT p.id,trim(p_title),trim(p_body),v_group,false,NULL,
  CASE WHEN p_target='individual' THEN 'direct_message' ELSE 'general' END
 FROM public.profiles p
 WHERE p.approved=true
 AND (p_target='todos' OR (p_target='individual' AND p.id=p_recipient)
    OR (p_target IN ('coroinha','pai','coordenadora') AND p.role=p_target));
 GET DIAGNOSTICS v_count=ROW_COUNT;
 IF v_count=0 THEN
  RAISE EXCEPTION 'Nenhum destinatário aprovado encontrado para o grupo selecionado.' USING ERRCODE='P0001';
 END IF;
 RETURN v_group;
END
$function$;
