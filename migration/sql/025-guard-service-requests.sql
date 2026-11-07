-- Neon-only: prevent requesting unpublished, expired, mismatched or occupied mass slots.
-- Apply in staging/clean rehearsal; Supabase production remains unchanged.
DO $guard$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM migration_private.environment WHERE id=true
   AND branch_id IN('br-rough-hill-bcj6lzt1','br-odd-bread-bc1jxzsh'))
 THEN RAISE EXCEPTION 'Unsupported branch' USING ERRCODE='42501'; END IF;
END $guard$;

ALTER POLICY requests_insert ON public.requests
WITH CHECK (
 public.is_approved()
 AND user_id=auth.uid()
 AND status='pendente'
 AND EXISTS(SELECT 1 FROM public.profiles me
            WHERE me.id=auth.uid() AND me.approved AND me.role='coroinha')
 AND EXISTS(
  SELECT 1 FROM public.masses m
  WHERE m.id=requests.mass_id AND m.published IS TRUE AND m.starts_at>now()
    AND (
      (requests.type='servir' AND requests.assignment_id IS NULL)
      OR
      (requests.type='substituir' AND requests.assignment_id IS NOT NULL
       AND EXISTS(SELECT 1 FROM public.assignments a
                  WHERE a.id=requests.assignment_id AND a.mass_id=m.id
                   AND a.status='desmarcado' AND a.server_id IS DISTINCT FROM auth.uid()))
    )
    AND NOT EXISTS(
      SELECT 1 FROM public.assignments mine
      WHERE mine.mass_id=m.id AND mine.server_id=auth.uid()
        AND mine.status IN('escalado','confirmado','presente')
    )
 )
);
