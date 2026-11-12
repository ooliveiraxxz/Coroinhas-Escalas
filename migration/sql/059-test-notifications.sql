-- Safe, rate-limited self-test to verify push on a real device.
CREATE OR REPLACE FUNCTION public.send_test_notification() RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $fn$
DECLARE v_user uuid:=auth.uid();v_pref jsonb;v_id uuid;
BEGIN
 IF v_user IS NULL OR NOT public.is_approved() THEN
  RAISE EXCEPTION 'Somente usuários aprovados podem testar notificações' USING ERRCODE='42501';
 END IF;
 SELECT notification_preferences INTO v_pref FROM public.profiles WHERE id=v_user;
 IF coalesce((v_pref->>'enabled')::boolean,true)=false
    OR coalesce((v_pref->>'general')::boolean,true)=false THEN
  RAISE EXCEPTION 'Ative avisos gerais em Ajustes para enviar um teste' USING ERRCODE='22023';
 END IF;
 IF EXISTS(SELECT 1 FROM public.notifications WHERE user_id=v_user
   AND title='Teste de notificações' AND created_at>now()-interval '1 minute') THEN
  RAISE EXCEPTION 'Aguarde um minuto antes de repetir o teste' USING ERRCODE='22023';
 END IF;
 INSERT INTO public.notifications(user_id,title,body,event_key)
 VALUES(v_user,'Teste de notificações','Este é um aviso de teste do Coroinhas-Escalas. Se chegou na tela bloqueada, o push está funcionando.','general')
 RETURNING id INTO v_id;
 RETURN v_id;
END $fn$;
