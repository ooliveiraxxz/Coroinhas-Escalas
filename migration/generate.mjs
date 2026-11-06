import fs from 'node:fs';
const read=n=>JSON.parse(fs.readFileSync(new URL(`audit/${n}.json`,import.meta.url)));
const out=[];
out.push(`-- ONLY the isolated migration branch. Never execute against Supabase or production.
-- Reviewed source snapshot: 2026-11-06. Apply once, atomically.
CREATE ROLE coroinhas_app NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS;
GRANT coroinhas_app TO coroinhas_owner;
CREATE SCHEMA migration_private;
REVOKE ALL ON SCHEMA migration_private FROM PUBLIC;
CREATE TABLE migration_private.environment (id boolean PRIMARY KEY DEFAULT true CHECK(id), branch_id text NOT NULL);
INSERT INTO migration_private.environment VALUES(true,'br-rough-hill-bcj6lzt1');
CREATE SCHEMA auth;
REVOKE ALL ON SCHEMA auth FROM PUBLIC;
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$ SELECT nullif(current_setting('app.user_id',true),'')::uuid $$;
REVOKE ALL ON FUNCTION auth.uid() FROM PUBLIC;
GRANT USAGE ON SCHEMA public,auth TO coroinhas_app;
GRANT EXECUTE ON FUNCTION auth.uid() TO coroinhas_app;
CREATE TABLE migration_private.identity_map(provider text NOT NULL,subject text NOT NULL,profile_id uuid NOT NULL REFERENCES public.profiles(id),PRIMARY KEY(provider,subject),UNIQUE(provider,profile_id));
INSERT INTO migration_private.identity_map SELECT 'supabase',id::text,id FROM public.profiles;
CREATE TABLE migration_private.push_outbox(notification_id uuid PRIMARY KEY REFERENCES public.notifications(id) ON DELETE CASCADE,created_at timestamptz NOT NULL DEFAULT now(),state text NOT NULL DEFAULT 'suppressed' CHECK(state IN ('suppressed','pending','sent','failed')));
CREATE FUNCTION migration_private.queue_push_notice() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$ BEGIN INSERT INTO migration_private.push_outbox(notification_id) VALUES(NEW.id) ON CONFLICT DO NOTHING; RETURN NEW; END $$;
REVOKE ALL ON FUNCTION migration_private.queue_push_notice() FROM PUBLIC;
CREATE TRIGGER queue_push AFTER INSERT ON public.notifications FOR EACH ROW EXECUTE FUNCTION migration_private.queue_push_notice();`);
const excluded=new Set(['on_signup','developer_manage_user','get_push_targets','rls_auto_enable','protect_profile','guard_notification_edit']);
for(const f of read('functions')){
 if(excluded.has(f.name)) continue;
 out.push(f.definition+';');
 out.push(`REVOKE ALL ON FUNCTION public.${f.name}(${f.args}) FROM PUBLIC;`);
 if(f.acl?.includes('authenticated='))out.push(`GRANT EXECUTE ON FUNCTION public.${f.name}(${f.args}) TO coroinhas_app;`);
}
out.push(`CREATE FUNCTION public.protect_profile() RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$
BEGIN
 IF NEW.id IS DISTINCT FROM OLD.id OR NEW.email IS DISTINCT FROM OLD.email THEN RAISE EXCEPTION 'Identidade imutável nesta fase' USING ERRCODE='42501'; END IF;
 IF NEW.role IS DISTINCT FROM OLD.role AND NOT public.is_developer() THEN RAISE EXCEPTION 'Somente desenvolvedor altera papéis' USING ERRCODE='42501'; END IF;
 IF (NEW.approved IS DISTINCT FROM OLD.approved OR NEW.notes IS DISTINCT FROM OLD.notes) AND NOT public.is_coordinator() THEN RAISE EXCEPTION 'Acesso restrito à coordenação' USING ERRCODE='42501'; END IF;
 IF NOT public.is_developer() AND OLD.role IN ('coordenadora','desenvolvedor') AND NEW.approved IS DISTINCT FROM OLD.approved THEN RAISE EXCEPTION 'Somente desenvolvedor gerencia perfis especiais' USING ERRCODE='42501'; END IF;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.protect_profile() FROM PUBLIC;
CREATE FUNCTION public.guard_notification_edit() RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$ BEGIN
 IF current_user='coroinhas_app' THEN RAISE EXCEPTION 'Use as funções autorizadas' USING ERRCODE='42501'; END IF; RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.guard_notification_edit() FROM PUBLIC;`);
for(const p of read('policies')){
 out.push(`CREATE POLICY "${p.policyname}" ON public."${p.tablename}" AS ${p.permissive} FOR ${p.cmd} TO coroinhas_app${p.qual?' USING ('+p.qual+')':''}${p.with_check?' WITH CHECK ('+p.with_check+')':''};`);
}
// Preserve effective data privileges, never copy TRUNCATE/TRIGGER/REFERENCES grants.
for(const g of read('schema')[0].inventory.grants){
 if(g.grantee==='authenticated'&&['SELECT','INSERT','UPDATE','DELETE'].includes(g.privilege_type))out.push(`GRANT ${g.privilege_type} ON public."${g.table_name}" TO coroinhas_app;`);
}
out.push('GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO coroinhas_app;');
for(const t of read('triggers')){
 if(t.schema!=='public'||t.name==='push_notice_insert')continue;
 out.push(t.definition+';');
}
out.push("SELECT setval(pg_get_serial_sequence('public.audit_log','id'),greatest(coalesce((select max(id) from public.audit_log),0)+1,1),false),setval(pg_get_serial_sequence('public.login_events','id'),greatest(coalesce((select max(id) from public.login_events),0)+1,1),false);");
out.push(`-- No auth.users mutations, no live HTTP webhook, no credentials copied.
-- Auth lifecycle management stays disabled until the identity migration is validated.`);
fs.writeFileSync(new URL('sql/001-isolated-security.sql',import.meta.url),out.join('\n\n').replaceAll('\r\n','\n')+'\n');
