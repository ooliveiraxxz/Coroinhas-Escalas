-- Only the isolated branch. Existing assignments and identifiers are preserved.
BEGIN;
DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM migration_private.environment WHERE branch_id='br-rough-hill-bcj6lzt1') THEN RAISE EXCEPTION 'Wrong branch'; END IF; END $$;
CREATE OR REPLACE FUNCTION public.guard_server_assignment() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF TG_OP='UPDATE' AND NEW.server_id IS NOT DISTINCT FROM OLD.server_id THEN RETURN NEW; END IF;
 IF NEW.server_id IS NOT NULL AND NOT EXISTS(
  SELECT 1 FROM public.profiles p WHERE p.id=NEW.server_id AND p.approved
   AND p.role IN ('coroinha','coordenadora','desenvolvedor')
 ) THEN RAISE EXCEPTION 'Somente um perfil aprovado que pode servir recebe funções.' USING ERRCODE='42501'; END IF;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.guard_server_assignment() FROM PUBLIC,coroinhas_app,coroinhas_gateway;
CREATE OR REPLACE TRIGGER guard_server_assignment BEFORE INSERT OR UPDATE OF server_id ON public.assignments FOR EACH ROW EXECUTE FUNCTION public.guard_server_assignment();
CREATE OR REPLACE TRIGGER guard_fixed_server BEFORE INSERT OR UPDATE OF server_id ON public.fixed_rules FOR EACH ROW EXECUTE FUNCTION public.guard_server_assignment();
COMMIT;
