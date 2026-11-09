-- Migração de vínculo pai-coroinha para Neon. Aplicada na branch br-rough-hill-bcj6lzt1 em 2026-11-09.

CREATE TABLE IF NOT EXISTS public.parent_child_links (parent_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,child_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,created_at timestamptz NOT NULL DEFAULT now(),PRIMARY KEY(parent_id,child_id),CHECK(parent_id<>child_id));

CREATE TABLE IF NOT EXISTS public.parent_link_challenges(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),parent_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,child_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,code_hash text NOT NULL,code_salt uuid NOT NULL,expires_at timestamptz NOT NULL,attempts integer NOT NULL DEFAULT 0 CHECK(attempts BETWEEN 0 AND 5),consumed_at timestamptz,created_at timestamptz NOT NULL DEFAULT now());

ALTER TABLE public.parent_child_links ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.parent_link_challenges ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.parent_child_links,public.parent_link_challenges FROM PUBLIC;

REVOKE ALL ON public.parent_child_links,public.parent_link_challenges FROM coroinhas_app;

CREATE OR REPLACE FUNCTION public.confirm_parent_link(p_challenge_id uuid, p_code text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v public.parent_link_challenges%rowtype;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.profiles WHERE id=auth.uid() AND approved AND role='pai') THEN RAISE EXCEPTION 'Acesso negado' USING ERRCODE='42501'; END IF;
 SELECT * INTO v FROM public.parent_link_challenges WHERE id=p_challenge_id AND parent_id=auth.uid() FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Solicitação não encontrada' USING ERRCODE='42501'; END IF;
 IF v.consumed_at IS NOT NULL OR v.expires_at<=now() OR v.attempts>=5 THEN RETURN false; END IF;
 UPDATE public.parent_link_challenges SET attempts=attempts+1 WHERE id=v.id;
 IF p_code IS NULL OR p_code !~ '^[0-9]{6}$' OR md5(v.code_salt::text||':'||p_code)<>v.code_hash THEN RETURN false; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.profiles WHERE id=v.child_id AND role='coroinha' AND approved) THEN RETURN false; END IF;
 INSERT INTO public.parent_child_links(parent_id,child_id) VALUES(v.parent_id,v.child_id) ON CONFLICT DO NOTHING;
 UPDATE public.parent_link_challenges SET consumed_at=now() WHERE id=v.id;
 INSERT INTO public.notifications(user_id,title,body,event_key) VALUES(v.child_id,'Responsável vinculado','Um responsável foi vinculado à sua conta. Você pode desfazer no Perfil.','parent_link_code');
 RETURN true;
END $function$
;

CREATE OR REPLACE FUNCTION public.list_parent_links()
 RETURNS TABLE(parent_id uuid, child_id uuid, parent_name text, child_name text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
SELECT l.parent_id,l.child_id,p.name::text,c.name::text FROM public.parent_child_links l JOIN public.profiles p ON p.id=l.parent_id AND p.role='pai' AND p.approved JOIN public.profiles c ON c.id=l.child_id AND c.role='coroinha' AND c.approved WHERE l.parent_id=auth.uid() OR l.child_id=auth.uid() OR public.is_coordinator() ORDER BY c.name $function$
;

CREATE OR REPLACE FUNCTION public.request_parent_link(p_child_email text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE p uuid:=auth.uid(); c uuid; code text; salt uuid:=gen_random_uuid(); challenge uuid; n bigint;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.profiles WHERE id=p AND approved AND role='pai') THEN RAISE EXCEPTION 'Somente responsáveis aprovados podem solicitar vínculos' USING ERRCODE='42501'; END IF;
 IF trim(coalesce(p_child_email,''))='' THEN RAISE EXCEPTION 'Informe o e-mail do coroinha'; END IF;
 SELECT id INTO c FROM public.profiles WHERE lower(email)=lower(trim(p_child_email)) AND role='coroinha' AND approved LIMIT 1;
 IF c IS NULL THEN RAISE EXCEPTION 'Conta de coroinha não localizada'; END IF;
 IF EXISTS(SELECT 1 FROM public.parent_child_links WHERE parent_id=p AND child_id=c) THEN RAISE EXCEPTION 'Vínculo já existente'; END IF;
 IF EXISTS(SELECT 1 FROM public.parent_link_challenges WHERE parent_id=p AND child_id=c AND created_at>now()-interval '1 minute') THEN RAISE EXCEPTION 'Aguarde um minuto para solicitar novo código'; END IF;
 IF (SELECT count(*) FROM public.parent_link_challenges WHERE parent_id=p AND created_at>now()-interval '1 hour')>=8 THEN RAISE EXCEPTION 'Limite de solicitações atingido'; END IF;
 SELECT ('x'||substr(replace(gen_random_uuid()::text,'-',''),1,8))::bit(32)::bigint INTO n;
 code:=lpad((n%1000000)::text,6,'0');
 INSERT INTO public.parent_link_challenges(parent_id,child_id,code_hash,code_salt,expires_at) VALUES(p,c,md5(salt::text||':'||code),salt,now()+interval '10 minutes') RETURNING id INTO challenge;
 INSERT INTO public.notifications(user_id,title,body,event_key) VALUES(c,'Código de vinculação do responsável','Código: '||code||'. Válido por 10 minutos. Informe apenas ao responsável que você reconhece.','parent_link_code');
 RETURN challenge;
END $function$
;

CREATE OR REPLACE FUNCTION public.unlink_parent_child(p_parent uuid, p_child uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN IF auth.uid() IS NULL OR (auth.uid()<>p_parent AND auth.uid()<>p_child AND NOT public.is_coordinator()) THEN RAISE EXCEPTION 'Acesso negado' USING ERRCODE='42501'; END IF; DELETE FROM public.parent_child_links WHERE parent_id=p_parent AND child_id=p_child; END $function$
;

REVOKE ALL ON FUNCTION public.request_parent_link(text),public.confirm_parent_link(uuid,text),public.list_parent_links(),public.unlink_parent_child(uuid,uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.request_parent_link(text),public.confirm_parent_link(uuid,text),public.list_parent_links(),public.unlink_parent_child(uuid,uuid) TO coroinhas_app;