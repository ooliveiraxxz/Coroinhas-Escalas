-- ESCALA SÃO BENTO - AJUSTE DE PRIVACIDADE DAS NOTIFICAÇÕES
-- HOMOLOGAÇÃO: não executar em produção sem testes de regressão e revisão de RLS.
-- "Enviar notificações" permite consultar apenas campanhas criadas pela própria conta.
-- "Receber notificações" permite consultar apenas avisos destinados à própria conta.
BEGIN;

ALTER POLICY notes_read ON public.notifications
USING (
  archived_at IS NULL AND (
    public.is_developer()
    OR (user_id = auth.uid() AND public.has_site_permission('read_notifications'))
    OR (created_by = auth.uid() AND public.has_site_permission('send_notifications'))
  )
);

COMMIT;
