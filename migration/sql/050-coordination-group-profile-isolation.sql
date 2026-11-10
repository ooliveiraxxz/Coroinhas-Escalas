-- Proteção entre coordenações: Coroinhas só gerenciam seus cadastros e responsáveis;
-- Cerimoniários só gerenciam os seus. O Desenvolvedor mantém o controle global.

CREATE OR REPLACE FUNCTION public.can_manage_profile(p_target uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
SELECT
 CASE WHEN public.is_developer() OR public.has_site_permission('manage_users') THEN true
 ELSE EXISTS (
   SELECT 1 FROM public.profiles manager
   JOIN public.profiles target ON target.id=p_target
   WHERE manager.id=auth.uid() AND manager.approved AND manager.role='coordenadora'
     AND (
       (manager.coordination_group='coroinha' AND target.role IN ('coroinha','pai'))
       OR (manager.coordination_group='cerimoniario' AND target.role='cerimoniario')
     )
 )
 END
$function$;

CREATE OR REPLACE FUNCTION public.protect_profile()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
BEGIN
 IF NEW.id IS DISTINCT FROM OLD.id OR NEW.email IS DISTINCT FROM OLD.email OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
  RAISE EXCEPTION 'Identidade imutável' USING ERRCODE='42501';
 END IF;
 IF (NEW.role IS DISTINCT FROM OLD.role OR NEW.coordination_group IS DISTINCT FROM OLD.coordination_group) AND NOT public.is_developer() THEN
  RAISE EXCEPTION 'Somente desenvolvedor altera papéis e grupos' USING ERRCODE='42501';
 END IF;
 IF (NEW.approved IS DISTINCT FROM OLD.approved OR NEW.notes IS DISTINCT FROM OLD.notes)
  AND NOT public.can_manage_profile(OLD.id) THEN
  RAISE EXCEPTION 'Sem permissão para administrar este cadastro' USING ERRCODE='42501';
 END IF;
 IF NOT public.is_developer() AND OLD.role IN ('coordenadora','desenvolvedor')
   AND NEW.approved IS DISTINCT FROM OLD.approved THEN
  RAISE EXCEPTION 'Conta administrativa protegida' USING ERRCODE='42501';
 END IF;
 RETURN NEW;
END $function$;

ALTER POLICY profile_self ON public.profiles USING (((id = auth.uid()) OR can_manage_profile(id))) WITH CHECK (((id = auth.uid()) OR can_manage_profile(id)));
