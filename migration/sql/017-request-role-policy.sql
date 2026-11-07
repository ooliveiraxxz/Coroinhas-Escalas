-- Somente homologação: preserva a correção já presente no banco em 07/11/2026.
BEGIN;
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM migration_private.environment WHERE branch_id='br-rough-hill-bcj6lzt1') THEN
  RAISE EXCEPTION 'Branch incorreta';
 END IF;
END $$;
ALTER POLICY requests_insert ON public.requests
 WITH CHECK (
  public.is_approved() AND user_id=auth.uid() AND status='pendente'
  AND EXISTS (
   SELECT 1 FROM public.profiles p
   WHERE p.id=auth.uid() AND p.approved AND p.role='coroinha'
  )
 );
COMMIT;
