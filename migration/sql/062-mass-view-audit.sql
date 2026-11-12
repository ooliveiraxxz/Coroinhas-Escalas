CREATE TABLE IF NOT EXISTS public.mass_views (mass_id uuid NOT NULL REFERENCES public.masses(id) ON DELETE CASCADE,user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,viewed_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(mass_id,user_id));

ALTER TABLE public.mass_views ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.mass_views FROM PUBLIC,coroinhas_app;

CREATE OR REPLACE FUNCTION public.record_mass_view(p_mass uuid) RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $fn$
DECLARE v_user uuid:=auth.uid();
BEGIN
 IF v_user IS NULL OR NOT public.is_approved() THEN RETURN false; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.masses WHERE id=p_mass AND published AND archived_at IS NULL) THEN RETURN false; END IF;
 INSERT INTO public.mass_views(mass_id,user_id,viewed_at) VALUES(p_mass,v_user,now())
 ON CONFLICT(mass_id,user_id) DO UPDATE SET viewed_at=excluded.viewed_at;
 RETURN true;
END $fn$;

CREATE OR REPLACE FUNCTION public.mass_viewers(p_mass uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $fn$
BEGIN
 IF NOT (public.has_site_permission('edit_coroinha') OR public.has_site_permission('edit_cerimoniario')) THEN RAISE EXCEPTION 'Sem permissão' USING ERRCODE='42501'; END IF;
 RETURN coalesce((SELECT jsonb_agg(jsonb_build_object('name',p.name,'viewed_at',v.viewed_at) ORDER BY v.viewed_at DESC)
 FROM public.mass_views v JOIN public.profiles p ON p.id=v.user_id WHERE v.mass_id=p_mass),'[]'::jsonb);
END $fn$;

REVOKE ALL ON FUNCTION public.record_mass_view(uuid), public.mass_viewers(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.record_mass_view(uuid),public.mass_viewers(uuid) TO coroinhas_app;
