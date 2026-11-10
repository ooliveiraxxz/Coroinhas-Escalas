-- Archive access does not authorize reading another recipient's private announcements.
CREATE OR REPLACE FUNCTION public.archive_list()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
 IF auth.uid() IS NULL OR NOT public.has_site_permission('view_archives') THEN
  RAISE EXCEPTION 'Acesso aos arquivados não autorizado' USING ERRCODE='42501';
 END IF;
 RETURN jsonb_build_object(
  'masses',coalesce((SELECT jsonb_agg(jsonb_build_object(
    'id',m.id,'title',m.title,'starts_at',m.starts_at,
    'location',m.location,'archived_at',m.archived_at,
    'expires_at',m.archived_at+interval '30 days',
    'assignments',(SELECT coalesce(jsonb_agg(jsonb_build_object(
      'function_name',a.function_name,'service_group',a.service_group,
      'status',a.status,'server',coalesce(p.name,'Vaga disponível')
    ) ORDER BY a.function_name),'[]'::jsonb)
    FROM public.assignments a LEFT JOIN public.profiles p ON p.id=a.server_id
    WHERE a.mass_id=m.id)
   ) ORDER BY m.starts_at DESC)
   FROM (SELECT * FROM public.masses WHERE archived_at IS NOT NULL ORDER BY starts_at DESC LIMIT 200)m),'[]'::jsonb),
  'notifications',coalesce((SELECT jsonb_agg(jsonb_build_object(
    'title',n.title,'body',n.body,'created_at',n.created_at,
    'archived_at',n.archived_at,'expires_at',n.archived_at+interval '30 days'
  ) ORDER BY n.created_at DESC)
  FROM (SELECT * FROM public.notifications WHERE archived_at IS NOT NULL AND
    (public.is_developer() OR user_id=auth.uid()) ORDER BY created_at DESC LIMIT 200)n),'[]'::jsonb),
  'polls',coalesce((SELECT jsonb_agg(jsonb_build_object(
    'question',p.question,'ends_at',p.ends_at,'archived_at',p.archived_at,
    'expires_at',p.archived_at+interval '30 days',
    'votes',(SELECT count(*) FROM public.poll_votes v WHERE v.poll_id=p.id)
  ) ORDER BY p.ends_at DESC) FROM (SELECT * FROM public.polls WHERE archived_at IS NOT NULL ORDER BY ends_at DESC LIMIT 150)p),'[]'::jsonb),
  'announcements',coalesce((SELECT jsonb_agg(jsonb_build_object(
    'title',a.title,'body',a.body,'created_at',a.created_at,
    'archived_at',a.archived_at,'expires_at',a.archived_at+interval '30 days'
  ) ORDER BY a.created_at DESC) FROM (SELECT * FROM public.screen_announcements WHERE archived_at IS NOT NULL AND
    (public.is_developer() OR target_role='all' OR target_user_id=auth.uid() OR
     (target_user_id IS NULL AND target_role=(SELECT role FROM public.profiles WHERE id=auth.uid())))
    ORDER BY created_at DESC LIMIT 150)a),'[]'::jsonb),
  'messages',coalesce((SELECT jsonb_agg(jsonb_build_object(
    'body',m.body,'type',m.type,'created_at',m.created_at,'archived_at',m.archived_at,
    'expires_at',m.archived_at+interval '30 days',
    'author',coalesce(p.name,'Usuário')
  ) ORDER BY m.created_at DESC)
  FROM (SELECT * FROM public.messages WHERE archived_at IS NOT NULL AND
    (public.is_developer() OR user_id=auth.uid()) ORDER BY created_at DESC LIMIT 150)m
  LEFT JOIN public.profiles p ON p.id=m.user_id),'[]'::jsonb),
  'support',coalesce((SELECT jsonb_agg(jsonb_build_object(
    'protocol',t.protocol,'category',t.category,'target_role',t.target_role,
    'closed_at',t.closed_at,'archived_at',t.archived_at,
    'expires_at',t.archived_at+interval '30 days',
    'messages',(SELECT coalesce(jsonb_agg(jsonb_build_object(
       'body',sm.body,'created_at',sm.created_at,
       'author',coalesce(pr.name,'Usuário')) ORDER BY sm.created_at),'[]'::jsonb)
       FROM public.support_chat_messages sm LEFT JOIN public.profiles pr ON pr.id=sm.sender_id
       WHERE sm.ticket_id=t.id)
  ) ORDER BY t.closed_at DESC) FROM (SELECT * FROM public.support_tickets WHERE archived_at IS NOT NULL AND
    (public.is_developer() OR requester_id=auth.uid()) ORDER BY closed_at DESC LIMIT 100)t),'[]'::jsonb)
 );
END $function$
;
