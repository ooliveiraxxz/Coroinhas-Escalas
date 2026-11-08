-- Reset intencional de dados da HOMOLOGAÇÃO (não executar no Supabase ou produção).
-- Mantém esquema, functions, triggers e RLS. Arquiva registros em migration_private.
DO $migration$
DECLARE
  t text;
  n integer;
  payload jsonb;
  current_count integer;
  target_names text[] := ARRAY['assignments','audit_log','banned_emails','fixed_rules','guides','login_events','masses','messages','notifications','profiles','push_subscriptions','requests','screen_announcement_dismissals','screen_announcements','site_updates'];
  deletion_order text[] := ARRAY['requests','assignments','fixed_rules','messages','screen_announcement_dismissals','screen_announcements','push_subscriptions','notifications','login_events','masses','site_updates','guides','banned_emails','profiles','audit_log'];
BEGIN
  IF current_database() <> 'coroinhas'
    OR NOT EXISTS(SELECT 1 FROM migration_private.environment WHERE branch_id='br-rough-hill-bcj6lzt1')
    OR (SELECT count(*) FROM pg_policies WHERE schemaname='public') <> 33
    OR (SELECT enabled FROM migration_private.push_runtime WHERE id=true) IS DISTINCT FROM false
    OR (SELECT count(*) FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE') <> 15
    THEN RAISE EXCEPTION 'Ambiente nao passou no gate do reset';
  END IF;
  IF EXISTS (SELECT 1 FROM neon_auth."user" WHERE email !~* '@example[.]invalid$')
    THEN RAISE EXCEPTION 'Contas Auth reais presentes: abortando reset';
  END IF;
  IF to_regclass('migration_private.cutover_reset_archive_20261108') IS NOT NULL
    THEN RAISE EXCEPTION 'Arquivo ja existe. Reset nao repetivel';
  END IF;
  CREATE TABLE migration_private.cutover_reset_archive_20261108(
    table_name text PRIMARY KEY,
    original_count integer NOT NULL,
    records jsonb NOT NULL,
    archived_at timestamptz NOT NULL DEFAULT now()
  );
  REVOKE ALL ON migration_private.cutover_reset_archive_20261108 FROM PUBLIC;
  FOREACH t IN ARRAY target_names LOOP
    EXECUTE format('SELECT count(*)::int,coalesce(jsonb_agg(to_jsonb(x)),''[]''::jsonb) FROM public.%I x',t) INTO n,payload;
    INSERT INTO migration_private.cutover_reset_archive_20261108(table_name,original_count,records) VALUES('public.'||t,n,payload);
  END LOOP;
  EXECUTE 'SELECT count(*)::int,coalesce(jsonb_agg(to_jsonb(x)),''[]''::jsonb) FROM migration_private.identity_map x' INTO n,payload;
  INSERT INTO migration_private.cutover_reset_archive_20261108(table_name,original_count,records) VALUES('migration_private.identity_map',n,payload);

  -- Anula vínculos antigos antes de eliminar profiles antigos; nao cria contas Auth.
  DELETE FROM migration_private.identity_map;
  FOREACH t IN ARRAY deletion_order LOOP
    EXECUTE format('DELETE FROM public.%I',t);
  END LOOP;
  FOREACH t IN ARRAY target_names LOOP
    EXECUTE format('SELECT count(*)::int FROM public.%I',t) INTO current_count;
    IF current_count <> 0 THEN RAISE EXCEPTION 'Limpeza incompleta: %.%',t,current_count; END IF;
  END LOOP;
  IF EXISTS (SELECT 1 FROM migration_private.identity_map) THEN RAISE EXCEPTION 'Mapas de identidade restantes';END IF;
END
$migration$;