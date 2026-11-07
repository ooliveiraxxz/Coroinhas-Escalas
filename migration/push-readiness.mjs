// Staging push readiness inventory. No push sending, no remote requests beyond read-only SQL.
import pg from 'pg';

const url=process.env.NEON_MIGRATION_ADMIN_DATABASE_URL;
if(!url)throw new Error('Requires a private, isolated Neon admin URL.');
const target=new URL(url);
if(!['postgres:','postgresql:'].includes(target.protocol)||
   !target.hostname.endsWith('.neon.tech')||
   target.pathname!=='/coroinhas'||
   decodeURIComponent(target.username)!=='coroinhas_owner')
 throw new Error('Only the isolated Neon maintenance database is permitted.');
const client=new pg.Client({connectionString:url});
try{
 await client.connect();
 await client.query('BEGIN READ ONLY');
 const {rows:branch}=await client.query('SELECT branch_id FROM migration_private.environment WHERE id=true');
 if(branch[0]?.branch_id!=='br-rough-hill-bcj6lzt1')throw new Error('Wrong branch, no operations executed.');
 const {rows}=await client.query(`
 SELECT
   (SELECT count(*)::int FROM migration_private.push_outbox) AS queued,
   (SELECT count(*)::int FROM migration_private.push_outbox WHERE state='suppressed') AS suppressed,
   (SELECT count(*)::int FROM migration_private.push_outbox WHERE state='pending') AS pending,
   (SELECT count(*)::int FROM public.push_subscriptions) AS subscriptions,
   (SELECT count(*)::int FROM public.push_subscriptions ps LEFT JOIN public.profiles p ON p.id=ps.user_id WHERE p.id IS NULL) AS orphan_subscriptions,
   (SELECT count(*)::int FROM migration_private.push_outbox o LEFT JOIN public.notifications n ON n.id=o.notification_id WHERE n.id IS NULL) AS orphan_queue_entries
 `);
 await client.query('ROLLBACK');
 // Deliberately return only aggregate counts, not endpoints, recipients or private keys.
 console.log(JSON.stringify({mode:'DRY_RUN_ONLY',deliveryEnabled:false,...rows[0]},null,2));
}catch{
 await client.query('ROLLBACK').catch(()=>{});
 console.error('Staging push audit failed; no notifications sent.');
 process.exitCode=1;
}finally{await client.end().catch(()=>{})}
