-- 090: fixed_rules uses Coroinha service group and has no service_group column.
-- Reuse the same permission-based eligibility as manual assignment.
CREATE OR REPLACE FUNCTION public.guard_fixed_member_assignment()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
BEGIN
 IF NEW.server_id IS NULL OR NOT public.is_eligible_service_member(NEW.server_id,'coroinha') THEN
  RAISE EXCEPTION 'Integrante sem permissão para ser escalado como coroinha'
  USING ERRCODE='42501';
 END IF;
 RETURN NEW;
END $function$;
DROP TRIGGER IF EXISTS guard_fixed_server ON public.fixed_rules;
CREATE TRIGGER guard_fixed_server BEFORE INSERT OR UPDATE OF server_id ON public.fixed_rules
FOR EACH ROW EXECUTE FUNCTION public.guard_fixed_member_assignment();
