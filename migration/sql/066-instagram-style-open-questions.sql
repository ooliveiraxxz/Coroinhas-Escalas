-- Text response question boxes, account scoped, with private answers.
CREATE TABLE IF NOT EXISTS public.open_questions (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 question text NOT NULL CHECK (length(trim(question)) BETWEEN 5 AND 500),
 target_role text NOT NULL CHECK(target_role IN ('coroinha','cerimoniario','pai','coordenadora','todos')),
 created_by uuid NOT NULL REFERENCES public.profiles(id),
 created_at timestamptz NOT NULL DEFAULT now(),
 ends_at timestamptz NOT NULL,
 archived_at timestamptz
);

CREATE TABLE IF NOT EXISTS public.open_question_answers (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 question_id uuid NOT NULL REFERENCES public.open_questions(id) ON DELETE CASCADE,
 user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
 answer text NOT NULL CHECK(length(trim(answer)) BETWEEN 1 AND 2000),
 created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(question_id,user_id)
);

ALTER TABLE public.open_questions ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.open_question_answers ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.open_questions, public.open_question_answers FROM PUBLIC,coroinhas_app;

CREATE OR REPLACE FUNCTION public.open_question_create(p_question text,p_target text,p_ends_at timestamptz)
 RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $fn$
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
 INSERT INTO public.notifications(user_id,title,body,event_key)
 SELECT p.id,'Nova pergunta para responder',left(trim(p_question),400),'general'
 FROM public.profiles p WHERE p.approved AND p.id<>v_user
 AND (p_target='todos' OR p.role=p_target)
 AND p.role<>'desenvolvedor';
 RETURN v_id;
END $fn$;

CREATE OR REPLACE FUNCTION public.open_question_list()
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $fn$
DECLARE v_user uuid:=auth.uid();v_role text;v_group text;
BEGIN
 IF v_user IS NULL OR NOT public.is_approved() THEN RAISE EXCEPTION 'Acesso negado' USING ERRCODE='42501'; END IF;
 SELECT role,coordination_group INTO v_role,v_group FROM public.profiles WHERE id=v_user;
 RETURN coalesce((
 SELECT jsonb_agg(jsonb_build_object(
 'id',q.id,'question',q.question,'ends_at',q.ends_at,'created_at',q.created_at,'target_role',q.target_role,
 'created_by',q.created_by,'creator_name',p.name,'answer',a.answer,
 'answer_count',CASE WHEN public.has_site_permission('manage_polls') AND (v_role='desenvolvedor' OR q.created_by=v_user) THEN
 (SELECT count(*) FROM public.open_question_answers x WHERE x.question_id=q.id) ELSE NULL END
 ) ORDER BY q.created_at DESC)
 FROM public.open_questions q JOIN public.profiles p ON p.id=q.created_by
 LEFT JOIN public.open_question_answers a ON a.question_id=q.id AND a.user_id=v_user
 WHERE q.archived_at IS NULL AND (
 (q.ends_at>now() AND (q.target_role='todos' OR q.target_role=v_role))
 OR (public.has_site_permission('manage_polls') AND (v_role='desenvolvedor' OR q.created_by=v_user))
 )
 ),'[]'::jsonb);
END $fn$;

CREATE OR REPLACE FUNCTION public.open_question_answer(p_question uuid,p_answer text)
 RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $fn$
DECLARE v_user uuid:=auth.uid();v_role text;v_q public.open_questions%rowtype;
BEGIN
 IF v_user IS NULL OR NOT public.is_approved() THEN RAISE EXCEPTION 'Acesso negado' USING ERRCODE='42501'; END IF;
 SELECT role INTO v_role FROM public.profiles WHERE id=v_user;
 SELECT * INTO v_q FROM public.open_questions WHERE id=p_question;
 IF NOT FOUND OR v_q.archived_at IS NOT NULL OR v_q.ends_at<=now() THEN RAISE EXCEPTION 'Pergunta encerrada ou indisponível' USING ERRCODE='22023'; END IF;
 IF v_q.target_role<>'todos' AND v_q.target_role<>v_role THEN RAISE EXCEPTION 'Pergunta de outro público' USING ERRCODE='42501'; END IF;
 IF length(trim(coalesce(p_answer,''))) NOT BETWEEN 1 AND 2000 THEN RAISE EXCEPTION 'Resposta deve ter até 2000 caracteres' USING ERRCODE='22023'; END IF;
 INSERT INTO public.open_question_answers(question_id,user_id,answer) VALUES(p_question,v_user,trim(p_answer))
 ON CONFLICT(question_id,user_id) DO NOTHING;
 IF NOT FOUND THEN RAISE EXCEPTION 'Você já respondeu esta pergunta' USING ERRCODE='22023'; END IF;
 INSERT INTO public.notifications(user_id,title,body,event_key)
 VALUES(v_q.created_by,'Nova resposta recebida',left(trim(p_answer),300),'general');
 RETURN true;
END $fn$;

CREATE OR REPLACE FUNCTION public.open_question_responses(p_question uuid)
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $fn$
DECLARE v_user uuid:=auth.uid();
BEGIN
 IF NOT public.has_site_permission('manage_polls') OR NOT EXISTS (
  SELECT 1 FROM public.open_questions q WHERE q.id=p_question
  AND (q.created_by=v_user OR public.is_developer())
 ) THEN RAISE EXCEPTION 'Acesso negado' USING ERRCODE='42501'; END IF;
 RETURN coalesce((
 SELECT jsonb_agg(jsonb_build_object('name',p.name,'answer',a.answer,'created_at',a.created_at) ORDER BY a.created_at DESC)
 FROM public.open_question_answers a JOIN public.profiles p ON p.id=a.user_id WHERE a.question_id=p_question
 ),'[]'::jsonb);
END $fn$;

REVOKE ALL ON FUNCTION public.open_question_create(text,text,timestamptz),public.open_question_list(),public.open_question_answer(uuid,text),public.open_question_responses(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.open_question_create(text,text,timestamptz),public.open_question_list(),public.open_question_answer(uuid,text),public.open_question_responses(uuid) TO coroinhas_app;
