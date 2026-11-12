-- Retain the question's deadline in the notification for accurate disabled trash status.
CREATE OR REPLACE FUNCTION public.open_question_create(p_question text, p_target text, p_ends_at timestamp with time zone)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_user uuid:=auth.uid();v_group text;v_role text;v_id uuid;
BEGIN
 IF NOT public.has_site_permission('manage_polls') THEN RAISE EXCEPTION 'Sem permissão' USING ERRCODE='42501'; END IF;
 SELECT role,coordination_group INTO v_role,v_group FROM public.profiles WHERE id=v_user AND approved;
 IF p_target NOT IN ('coroinha','cerimoniario','pai','coordenadora','todos') THEN RAISE EXCEPTION 'Público inválido' USING ERRCODE='22023'; END IF;
 IF v_role<>'desenvolvedor' AND p_target<>v_group THEN RAISE EXCEPTION 'Somente perguntas para seu grupo' USING ERRCODE='42501'; END IF;
 IF length(trim(coalesce(p_question,''))) NOT BETWEEN 5 AND 500 THEN RAISE EXCEPTION 'Escreva uma pergunta de 5 a 500 caracteres' USING ERRCODE='22023'; END IF;
 IF p_ends_at<=now() OR p_ends_at>now()+interval '90 days' THEN RAISE EXCEPTION 'Prazo inválido' USING ERRCODE='22023'; END IF;
 INSERT INTO public.open_questions(question,target_role,created_by,ends_at)
 VALUES(trim(p_question),p_target,v_user,p_ends_at) RETURNING id INTO v_id;
 INSERT INTO public.notifications(user_id,title,body,event_key,group_id,priority_until)
 SELECT p.id,'Nova pergunta para responder',left(trim(p_question),400),'open_questions',v_id,p_ends_at
 FROM public.profiles p WHERE p.approved AND p.id<>v_user
 AND (p_target='todos' OR p.role=p_target)
 AND p.role<>'desenvolvedor';
 RETURN v_id;
END $function$
;
