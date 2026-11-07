-- Executada somente em br-rough-hill-bcj6lzt1, em 07/11/2026.
-- Defesa em profundidade: marcar como visto apenas avisos ativos e enderecados ao próprio usuário.
-- Nenhuma política da produção Supabase é alterada.
DO $guard$
BEGIN
 IF NOT EXISTS (SELECT 1 FROM migration_private.environment WHERE branch_id='br-rough-hill-bcj6lzt1')
 THEN RAISE EXCEPTION 'Branch incorreta' USING ERRCODE='42501'; END IF;
END $guard$;
ALTER POLICY screen_dismissals_insert ON public.screen_announcement_dismissals
 WITH CHECK (
 user_id=(SELECT auth.uid()) AND EXISTS (
 SELECT 1 FROM public.screen_announcements a
 JOIN public.profiles me ON me.id=(SELECT auth.uid())
 WHERE a.id=announcement_id AND a.active AND me.approved
 AND (a.target_role='all' OR (a.target_role='individual' AND a.target_user_id=me.id) OR a.target_role=me.role)
 ));
ALTER POLICY screen_dismissals_update ON public.screen_announcement_dismissals
 USING (user_id=(SELECT auth.uid()))
 WITH CHECK (
 user_id=(SELECT auth.uid()) AND EXISTS (
 SELECT 1 FROM public.screen_announcements a
 JOIN public.profiles me ON me.id=(SELECT auth.uid())
 WHERE a.id=announcement_id AND a.active AND me.approved
 AND (a.target_role='all' OR (a.target_role='individual' AND a.target_user_id=me.id) OR a.target_role=me.role)
 ));
