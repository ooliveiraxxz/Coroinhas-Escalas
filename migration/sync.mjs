// Manual, one-way synchronization into the isolated branch only. Never deletes.
import fs from 'node:fs';
import pg from 'pg';
const inventory=JSON.parse(fs.readFileSync(new URL('./audit/schema.json',import.meta.url)))[0].inventory;
const tables=['profiles','masses','assignments','requests','notifications','messages','guides','fixed_rules','site_updates','audit_log','banned_emails','login_events','push_subscriptions','screen_announcements','screen_announcement_dismissals'];
const allowlistedBranches=new Set(['br-rough-hill-bcj6lzt1','br-odd-bread-bc1jxzsh']);
const targetBranch=process.env.MIGRATION_TARGET_BRANCH_ID||'br-rough-hill-bcj6lzt1';
if(!allowlistedBranches.has(targetBranch))
 throw new Error('Refusing synchronization to any unapproved Neon branch.');
const apply=process.argv.includes('--apply');
const confirmed=process.argv.includes('--confirm-isolated-neon');
const reviewedPath=process.argv.find(a=>a.startsWith('--reviewed-plan='))?.slice('--reviewed-plan='.length);
if(apply&&!reviewedPath)throw new Error('Apply requires an explicitly reviewed read-only plan.');
const reviewed=reviewedPath?JSON.parse(fs.readFileSync(reviewedPath,'utf8')):null;
const sourceUrl=process.env.SOURCE_READONLY_DATABASE_URL;
// This offline maintenance tool needs full table visibility for accurate checksums.
// Never reuse the privileged admin URL in the Vercel application's gateway.
const targetUrl=process.env.NEON_MIGRATION_ADMIN_DATABASE_URL;
if(apply&&!confirmed)throw new Error('Refusing sync without --confirm-isolated-neon.');
if(!sourceUrl||!targetUrl)throw new Error('Supply private source and target connection URLs for this mode.');
if(sourceUrl===targetUrl)throw new Error('Source and destination must differ.');
if(decodeURIComponent(new URL(targetUrl).username)!=='coroinhas_owner')
 throw new Error('Explicit --apply requires isolated branch owner connection.');
const source=new pg.Client({connectionString:sourceUrl}),target=new pg.Client({connectionString:targetUrl});
const id=s=>'"'+s.replaceAll('"','""')+'"';
try {
 await source.connect();await target.connect();
 await source.query('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY');
 await target.query(apply?'BEGIN':'BEGIN READ ONLY');
 const {rows:marker}=await target.query('SELECT branch_id FROM migration_private.environment WHERE id=true');
 if(marker[0]?.branch_id!==targetBranch)throw new Error('Target is not the explicitly selected isolated branch.');
 // A fingerprint of the source project is required, not a guessed hostname.
 const expected=process.env.MIGRATION_SOURCE_PROJECT;
 if(expected!=='dsglwwwwdtjynipauvrp')throw new Error('Set the expected source project explicitly.');
 const u=new URL(sourceUrl);
 const sourceHostOK=u.hostname==='db.'+expected+'.supabase.co'||u.hostname===expected+'.supabase.co'||
  (u.hostname.endsWith('.pooler.supabase.com')&&decodeURIComponent(u.username).split('.').includes(expected));
 if(!sourceHostOK)throw new Error('Source project mismatch.');
 const targetAddress=new URL(targetUrl);
 if(!['postgres:','postgresql:'].includes(targetAddress.protocol)||
    !targetAddress.hostname.endsWith('.neon.tech')||
    targetAddress.pathname!=='/coroinhas'||
    decodeURIComponent(targetAddress.username)!=='coroinhas_owner')throw new Error('Target must be the isolated Neon project owner database.');

 // Hold destination stable while validating the reviewed fingerprints and applying.
 if(apply)for(const table of tables)await target.query(`LOCK TABLE public.${id(table)} IN SHARE ROW EXCLUSIVE MODE`);
 const fingerprints=[];
 for(const table of tables){
  const q=`SELECT count(*)::int count,md5(coalesce(string_agg(to_jsonb(t)::text,chr(10) ORDER BY to_jsonb(t)::text),'')) checksum FROM public.${id(table)} t`;
  const a=(await source.query(q)).rows[0],b=(await target.query(q)).rows[0];
  fingerprints.push({table,sourceCount:a.count,targetCount:b.count,sourceChecksum:a.checksum,targetChecksum:b.checksum});
 }
 if(apply&&(reviewed?.sourceProject!==expected||reviewed?.targetBranch!==targetBranch||JSON.stringify(reviewed?.fingerprints)!==JSON.stringify(fingerprints)))
  throw new Error('Reviewed plan missing, stale or conflicting; no data written.');
 const snapshots=[],conflicts=[];
 for(const table of tables){
  const pk=inventory.constraints.find(c=>c.table_name===table&&c.contype==='p');
  if(!pk)throw new Error('Missing primary key: '+table);
  const keys=pk.definition.match(/\(([^)]+)\)/)[1].split(',').map(s=>s.trim());
  const cols=inventory.columns.filter(c=>c.table_name===table).map(c=>c.column_name);
  const data=await source.query(`SELECT to_jsonb(t) AS row FROM public.${id(table)} t`);
  const payload=JSON.stringify(data.rows.map(r=>r.row));
  // Fail on source deletions; never silently retain or remove divergent rows.
  const extra=await target.query(`SELECT count(*)::int count FROM public.${id(table)} t WHERE NOT EXISTS(SELECT 1 FROM jsonb_populate_recordset(NULL::public.${id(table)},$1::jsonb) s WHERE ${keys.map(k=>`s.${id(k)}=t.${id(k)}`).join(' AND ')})`,[payload]);
  if(extra.rows[0].count){
   conflicts.push({table,targetOnlyCount:extra.rows[0].count});
   if(apply)throw new Error('Deletion/conflict review required for '+table);
  }
  snapshots.push({table,keys,cols,payload,count:data.rowCount});
 }
 if(!apply){
  // Default read-only audit: no user records, tokens or credentials are logged.
  const differences=fingerprints.filter(r=>r.sourceCount!==r.targetCount||r.sourceChecksum!==r.targetChecksum);
  await target.query('ROLLBACK');await source.query('ROLLBACK');
  console.log(JSON.stringify({mode:'read-only',sourceProject:expected,targetBranch,fingerprints,tablesCompared:tables.length,differences,conflicts,requiresConflictReview:conflicts.length>0,dataChecksMatch:differences.length===0&&conflicts.length===0,requiresFunctionalValidation:true},null,2));
 }else{
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
 }
} catch(e) {
 await target.query('ROLLBACK').catch(()=>{});await source.query('ROLLBACK').catch(()=>{});
 // Do not log driver errors, query details, row content or credentials.
 console.error('Synchronization stopped; target transaction rolled back. Inspect privately before retrying.');
 process.exitCode=1;
} finally {await source.end().catch(()=>{});await target.end().catch(()=>{})}
