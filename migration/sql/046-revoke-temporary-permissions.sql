-- Revoke all active temporary rules for a selected person/capability.
-- Prevents an older temporary grant from becoming active again after a later revocation.
CREATE OR REPLACE FUNCTION public.developer_revoke_permission(p_id uuid, p_confirmation text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_user uuid;v_key text;v_count integer;
BEGIN
 IF NOT public.is_developer() OR trim(coalesce(p_confirmation,''))<>'DESENVOLVEDOR' THEN
  RAISE EXCEPTION 'Confirmação inválida' USING ERRCODE='42501';
 END IF;
 SELECT subject_user,permission_key INTO v_user,v_key
 FROM public.permission_rules WHERE id=p_id AND subject_user IS NOT NULL AND expires_at>now();
 IF NOT FOUND THEN RETURN false; END IF;
 DELETE FROM public.permission_rules
 WHERE subject_user=v_user AND permission_key=v_key AND expires_at>now();
 GET DIAGNOSTICS v_count=ROW_COUNT;
 RETURN v_count>0;
END $function$;
