-- HOMOLOGAÇÃO: duas permissões independentes para o painel de Mensagens.
-- Aplique primeiro no ramo Neon de homologação. Não altera perfis ou mensagens existentes.
BEGIN;

INSERT INTO public.permission_catalog(key,category,label,default_roles,sensitive) VALUES
 ('view_messages','Coordenação','Consultar mensagens da coordenação',ARRAY['coordenadora','desenvolvedor']::text[],true),
 ('mark_messages_seen','Coordenação','Marcar mensagens da coordenação como vistas',ARRAY['coordenadora','desenvolvedor']::text[],true)
ON CONFLICT(key) DO UPDATE SET category=EXCLUDED.category,label=EXCLUDED.label,
 default_roles=EXCLUDED.default_roles,sensitive=EXCLUDED.sensitive;

ALTER POLICY messages_read ON public.messages
USING (archived_at IS NULL AND (user_id=auth.uid() OR public.has_site_permission('view_messages')));

CREATE OR REPLACE FUNCTION public.mark_coordinator_message_seen(p_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
BEGIN
 IF auth.uid() IS NULL OR NOT public.has_site_permission('mark_messages_seen')
    OR NOT public.has_site_permission('view_messages')
 THEN RAISE EXCEPTION 'Sem permissão para marcar mensagens como vistas' USING ERRCODE='42501'; END IF;
 UPDATE public.messages SET seen=true,read_at=now() WHERE id=p_id AND seen=false AND archived_at IS NULL;
END
$function$;

COMMIT;
