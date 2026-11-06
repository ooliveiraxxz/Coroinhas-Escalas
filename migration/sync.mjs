// Manual, one-way synchronization into the isolated branch only. Never deletes.
import fs from 'node:fs';
import pg from 'pg';
const inventory=JSON.parse(fs.readFileSync(new URL('./audit/schema.json',import.meta.url)))[0].inventory;
const tables=['profiles','masses','assignments','requests','notifications','messages','guides','fixed_rules','site_updates','audit_log','banned_emails','login_events','push_subscriptions','screen_announcements','screen_announcement_dismissals'];
const sourceUrl=process.env.SOURCE_READONLY_DATABASE_URL;
const targetUrl=process.env.NEON_MIGRATION_DATABASE_URL;
if(!sourceUrl||!targetUrl)throw new Error('Supply SOURCE_READONLY_DATABASE_URL and NEON_MIGRATION_DATABASE_URL privately.');
if(sourceUrl===targetUrl)throw new Error('Source and destination must differ.');
const source=new pg.Client({connectionString:sourceUrl}),target=new pg.Client({connectionString:targetUrl});
const id=s=>'"'+s.replaceAll('"','""')+'"';
try {
 await source.connect();await target.connect();
 await source.query('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY');
 await target.query('BEGIN');
 const {rows:marker}=await target.query('SELECT branch_id FROM migration_private.environment WHERE id=true');
 if(marker[0]?.branch_id!=='br-rough-hill-bcj6lzt1')throw new Error('Target is not the authorized isolated branch.');
 // A fingerprint of the source project is required, not a guessed hostname.
 const expected=process.env.MIGRATION_SOURCE_PROJECT;
 if(expected!=='dsglwwwwdtjynipauvrp')throw new Error('Set the expected source project explicitly.');
 const u=new URL(sourceUrl);
 if(!u.hostname.includes(expected)&&!decodeURIComponent(u.username).includes(expected))throw new Error('Source project mismatch.');
 const snapshots=[];
 for(const table of tables){
  const pk=inventory.constraints.find(c=>c.table_name===table&&c.contype==='p');
  if(!pk)throw new Error('Missing primary key: '+table);
  const keys=pk.definition.match(/\(([^)]+)\)/)[1].split(',').map(s=>s.trim());
  const cols=inventory.columns.filter(c=>c.table_name===table).map(c=>c.column_name);
  const data=await source.query(`SELECT to_jsonb(t) AS row FROM public.${id(table)} t`);
  const payload=JSON.stringify(data.rows.map(r=>r.row));
  // Fail on source deletions; never silently retain or remove divergent rows.
  const extra=await target.query(`SELECT count(*)::int count FROM public.${id(table)} t WHERE NOT EXISTS(SELECT 1 FROM jsonb_populate_recordset(NULL::public.${id(table)},$1::jsonb) s WHERE ${keys.map(k=>`s.${id(k)}=t.${id(k)}`).join(' AND ')})`,[payload]);
  if(extra.rows[0].count)throw new Error('Deletion/conflict review required for '+table);
  snapshots.push({table,keys,cols,payload,count:data.rowCount});
 }
 // Prevent imported rows from generating fresh audit/notification events.
 // Foreign-key constraint triggers remain active.
 for(const {table} of snapshots)await target.query(`ALTER TABLE public.${id(table)} DISABLE TRIGGER USER`);
 for(const {table,keys,cols,payload} of snapshots){
  const changed=cols.filter(c=>!keys.includes(c));
  const conflict=changed.length?'DO UPDATE SET '+changed.map(c=>`${id(c)}=EXCLUDED.${id(c)}`).join(',')+` WHERE (${changed.map(c=>'t.'+id(c)).join(',')}) IS DISTINCT FROM (${changed.map(c=>'EXCLUDED.'+id(c)).join(',')})`:'DO NOTHING';
  await target.query(`INSERT INTO public.${id(table)} AS t (${cols.map(id).join(',')}) OVERRIDING SYSTEM VALUE SELECT ${cols.map(id).join(',')} FROM jsonb_populate_recordset(NULL::public.${id(table)},$1::jsonb) ON CONFLICT (${keys.map(id).join(',')}) ${conflict}`,[payload]);
 }
 for(const {table} of snapshots)await target.query(`ALTER TABLE public.${id(table)} ENABLE TRIGGER USER`);
 for(const table of ['audit_log','login_events'])await target.query(`SELECT setval(pg_get_serial_sequence($1,'id'),greatest(coalesce((SELECT max(id) FROM public.${id(table)}),0)+1,1),false)`,['public.'+table]);
 await target.query("INSERT INTO migration_private.identity_map SELECT 'supabase',id::text,id FROM public.profiles ON CONFLICT DO NOTHING");
 const checks=[];
 for(const {table,count} of snapshots){
  const query=`SELECT md5(coalesce(string_agg(to_jsonb(t)::text,E'\\n' ORDER BY to_jsonb(t)::text),'')) checksum FROM public.${id(table)} t`;
  const a=await source.query(query),b=await target.query(query);
  if(a.rows[0].checksum!==b.rows[0].checksum)throw new Error('Checksum mismatch: '+table);
  checks.push({table,count,match:true});
 }
 await target.query('COMMIT');await source.query('ROLLBACK');
 console.log(JSON.stringify({synced:true,tables:checks},null,2));
} catch(e) {
 await target.query('ROLLBACK').catch(()=>{});await source.query('ROLLBACK').catch(()=>{});
 // Do not log driver errors, query details, row content or credentials.
 console.error('Synchronization stopped; target transaction rolled back. Inspect privately before retrying.');
 process.exitCode=1;
} finally {await source.end().catch(()=>{});await target.end().catch(()=>{})}
