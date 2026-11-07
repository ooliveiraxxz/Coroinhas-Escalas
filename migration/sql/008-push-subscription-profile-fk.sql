-- ONLY on the isolated Neon branch br-rough-hill-bcj6lzt1.
-- The original Supabase FK points to auth.users, which does not share Neon Auth identifiers.
-- Keep the original public profile UUID as the stable owner of push subscriptions.
-- RESTRICT deletion is deliberate: prevent accidental loss of a subscription/profile.
DO $guard$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM migration_private.environment WHERE branch_id='br-rough-hill-bcj6lzt1')
 THEN RAISE EXCEPTION 'Wrong staging branch' USING ERRCODE='42501'; END IF;
 IF EXISTS(SELECT 1 FROM public.push_subscriptions s LEFT JOIN public.profiles p ON p.id=s.user_id WHERE p.id IS NULL)
 THEN RAISE EXCEPTION 'Cannot add FK while orphan subscriptions exist'; END IF;
END $guard$;
ALTER TABLE public.push_subscriptions
 ADD CONSTRAINT push_subscriptions_profile_fkey
 FOREIGN KEY(user_id) REFERENCES public.profiles(id)
 ON DELETE RESTRICT;
