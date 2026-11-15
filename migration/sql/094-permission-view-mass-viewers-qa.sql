-- EXCLUSIVAMENTE HOMOLOGAÇÃO: falling-dawn-14662789 / br-silent-firefly-be780j5s
-- Não aplicar no ambiente oficial sem autorização explícita.
BEGIN;
INSERT INTO public.permission_catalog(key, category, label, default_roles, sensitive)
VALUES ('view_mass_viewers', 'Escalas', 'Ver quem visualizou a escala', ARRAY['desenvolvedor']::text[], true)
ON CONFLICT (key) DO UPDATE
SET category=EXCLUDED.category, label=EXCLUDED.label, default_roles=EXCLUDED.default_roles, sensitive=EXCLUDED.sensitive;

CREATE OR REPLACE FUNCTION public.mass_viewers(p_mass uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
BEGIN
 IF NOT public.has_site_permission('view_mass_viewers') THEN
  RAISE EXCEPTION 'Sem permissão para visualizar quem viu esta escala' USING ERRCODE='42501';
 END IF;
 RETURN coalesce((
  SELECT jsonb_agg(jsonb_build_object('name',p.name,'viewed_at',v.viewed_at) ORDER BY v.viewed_at DESC)
  FROM public.mass_views v JOIN public.profiles p ON p.id=v.user_id WHERE v.mass_id=p_mass
 ),'[]'::jsonb);
END $function$;
COMMIT;
