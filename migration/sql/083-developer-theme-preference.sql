-- Developer-only visual preference. Does not affect role, coordination_group or permissions.
-- Two supported values: coroinha and cerimoniario.
ALTER TABLE public.profiles
 ADD COLUMN IF NOT EXISTS theme_preference text NOT NULL DEFAULT 'coroinha';
ALTER TABLE public.profiles
 DROP CONSTRAINT IF EXISTS profiles_theme_preference_check;
ALTER TABLE public.profiles
 ADD CONSTRAINT profiles_theme_preference_check
 CHECK (theme_preference IN ('coroinha','cerimoniario'));

-- The gateway cannot directly update profiles; this narrowly scoped RPC
-- changes ONLY the signed-in approved developer's own theme.
CREATE OR REPLACE FUNCTION public.developer_set_my_theme(p_theme text)
RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_id uuid;
BEGIN
 v_id:=auth.uid();
 IF v_id IS NULL THEN
  RAISE EXCEPTION 'Autenticação necessária' USING ERRCODE='42501';
 END IF;
 IF p_theme IS NULL OR p_theme NOT IN ('coroinha','cerimoniario') THEN
  RAISE EXCEPTION 'Tema inválido' USING ERRCODE='22023';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM public.profiles
    WHERE id=v_id AND approved=true AND role='desenvolvedor') THEN
  RAISE EXCEPTION 'Apenas desenvolvedores podem escolher o tema' USING ERRCODE='42501';
 END IF;
 UPDATE public.profiles SET theme_preference=p_theme WHERE id=v_id;
 RETURN p_theme;
END;
$function$;
REVOKE ALL ON FUNCTION public.developer_set_my_theme(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.developer_set_my_theme(text) TO coroinhas_app;
