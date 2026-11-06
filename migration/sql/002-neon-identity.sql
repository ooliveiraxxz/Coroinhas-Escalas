-- Only br-rough-hill-bcj6lzt1, apply once in a transaction.
CREATE FUNCTION migration_private.resolve_neon_identity(p_subject uuid,p_session uuid,p_requested_role text DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE u neon_auth."user"%rowtype; v_profile uuid;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM migration_private.environment WHERE branch_id='br-rough-hill-bcj6lzt1') THEN RAISE EXCEPTION 'Wrong branch' USING ERRCODE='42501';END IF;
 SELECT * INTO u FROM neon_auth."user" WHERE id=p_subject;
 IF u.id IS NULL OR NOT u."emailVerified" OR coalesce(u.banned,false) OR NOT EXISTS(SELECT 1 FROM neon_auth.session WHERE id=p_session AND "userId"=p_subject AND "expiresAt">now()) THEN RAISE EXCEPTION 'Invalid session' USING ERRCODE='42501';END IF;
 IF EXISTS(SELECT 1 FROM public.banned_emails WHERE email=lower(u.email)) THEN RAISE EXCEPTION 'Blocked' USING ERRCODE='42501';END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(p_subject::text,0));
 SELECT profile_id INTO v_profile FROM migration_private.identity_map WHERE provider='neon' AND subject=p_subject::text;
 IF v_profile IS NOT NULL THEN RETURN v_profile; END IF;
 -- Existing emails never self-link: migration mappings are reserved by an administrator.
 IF EXISTS(SELECT 1 FROM public.profiles WHERE lower(email)=lower(u.email)) THEN RAISE EXCEPTION 'Identity linking required' USING ERRCODE='42501';END IF;
 IF p_requested_role IS NULL OR p_requested_role NOT IN ('coroinha','pai') THEN RAISE EXCEPTION 'Profile registration required' USING ERRCODE='42501';END IF;
 INSERT INTO public.profiles(id,name,email,role,approved) VALUES(u.id,coalesce(u.name,''),u.email,p_requested_role,false);
 INSERT INTO migration_private.identity_map VALUES('neon',u.id::text,u.id);
 RETURN u.id;
END $$;
REVOKE ALL ON FUNCTION migration_private.resolve_neon_identity(uuid,uuid,text) FROM PUBLIC;
-- A NOINHERIT gateway login gets EXECUTE and membership of coroinhas_app separately.
