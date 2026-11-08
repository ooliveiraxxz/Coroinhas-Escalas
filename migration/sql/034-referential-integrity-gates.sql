-- Read-only referential integrity validation. Compatible with both
-- isolated branches and safe to repeat after every synchronization.
DO $audit$
DECLARE invalid integer;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM migration_private.environment
 WHERE id=true AND branch_id IN('br-rough-hill-bcj6lzt1','br-odd-bread-bc1jxzsh'))
 THEN RAISE EXCEPTION 'Wrong branch';END IF;
 SELECT
 (SELECT count(*) FROM public.assignments a
  LEFT JOIN public.masses m ON m.id=a.mass_id WHERE m.id IS NULL)
 +(SELECT count(*) FROM public.assignments a
  LEFT JOIN public.profiles p ON p.id=a.server_id
  WHERE a.server_id IS NOT NULL AND p.id IS NULL)
 +(SELECT count(*) FROM public.requests r
  LEFT JOIN public.profiles p ON p.id=r.user_id WHERE p.id IS NULL)
 +(SELECT count(*) FROM public.requests r
  LEFT JOIN public.assignments a ON a.id=r.assignment_id
  WHERE r.assignment_id IS NOT NULL
   AND (a.id IS NULL OR a.mass_id<>r.mass_id))
 +(SELECT count(*) FROM public.notifications n
  LEFT JOIN public.profiles p ON p.id=n.user_id WHERE p.id IS NULL)
 +(SELECT count(*) FROM public.push_subscriptions s
  LEFT JOIN public.profiles p ON p.id=s.user_id WHERE p.id IS NULL)
 +(SELECT count(*) FROM migration_private.identity_map i
  LEFT JOIN public.profiles p ON p.id=i.profile_id WHERE p.id IS NULL)
 INTO invalid;
 IF invalid>0 THEN RAISE EXCEPTION 'Migration relationship inconsistencies found: %',invalid;END IF;
 IF EXISTS (SELECT 1 FROM public.profiles p WHERE p.approved AND
   p.role='coroinha' AND lower(p.email) LIKE '%@example.invalid')
 THEN RAISE EXCEPTION 'Approved test fixture unexpectedly active';END IF;
END $audit$;
