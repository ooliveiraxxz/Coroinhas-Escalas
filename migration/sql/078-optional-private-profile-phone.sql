-- Optional personal phone, not used for login, not exposed in the profile directory.
CREATE TABLE IF NOT EXISTS migration_private.profile_phones(user_id uuid PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,phone text NOT NULL CHECK (phone ~ '^55[1-9][0-9]{9,10}$'),updated_at timestamptz NOT NULL DEFAULT now());

REVOKE ALL ON migration_private.profile_phones FROM PUBLIC,coroinhas_app;

CREATE OR REPLACE FUNCTION public.my_phone() RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $fn$
DECLARE v_user uuid:=auth.uid();
BEGIN
 IF v_user IS NULL OR NOT public.is_approved() THEN RAISE EXCEPTION 'Acesso negado' USING ERRCODE='42501'; END IF;
 RETURN (SELECT phone FROM migration_private.profile_phones WHERE user_id=v_user);
END $fn$;

CREATE OR REPLACE FUNCTION public.update_my_phone(p_phone text) RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $fn$
DECLARE v_user uuid:=auth.uid();v_phone text:=regexp_replace(coalesce(p_phone,''),'[^0-9]','','g');
BEGIN
 IF v_user IS NULL OR NOT public.is_approved() THEN RAISE EXCEPTION 'Acesso negado' USING ERRCODE='42501'; END IF;
 IF v_phone='' THEN
  DELETE FROM migration_private.profile_phones WHERE user_id=v_user;
  RETURN NULL;
 END IF;
 IF length(v_phone) IN (10,11) THEN v_phone:='55'||v_phone; END IF;
 IF v_phone !~ '^55[1-9][0-9]{9,10}$' THEN
  RAISE EXCEPTION 'Informe um telefone brasileiro válido com DDD' USING ERRCODE='22023';
 END IF;
 INSERT INTO migration_private.profile_phones(user_id,phone,updated_at) VALUES(v_user,v_phone,now())
 ON CONFLICT(user_id) DO UPDATE SET phone=excluded.phone,updated_at=now();
 RETURN v_phone;
END $fn$;

REVOKE ALL ON FUNCTION public.my_phone(),public.update_my_phone(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.my_phone(),public.update_my_phone(text) TO coroinhas_app;
