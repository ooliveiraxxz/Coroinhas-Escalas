import {Pool} from 'pg';
import webpush from 'web-push';
import {migrationEnabled} from '@/lib/auth/server';
import {dispatchPushBatch,type PushDatabase} from '@/lib/neon/push-dispatch';

let pool:Pool|undefined;
const publicKey=()=>process.env.NEXT_PUBLIC_VAPID_PUBLIC_KEY;
const privateKey=()=>process.env.VAPID_PRIVATE_KEY;
const subject=()=>process.env.VAPID_SUBJECT;

/** Only sends opt-in notifications queued after activation, with a restricted Neon role. */
export async function dispatchNeonPush(limit=10){
 if(!migrationEnabled()||process.env.VERCEL_ENV!=='production'||
    process.env.NEON_PUSH_DISPATCH_ENABLED!=='true')return {processed:0,sent:0,failed:0,skipped:0};
 if(!publicKey()||!privateKey()||!subject())throw new Error('VAPID configuration incomplete');
 const uri=process.env.NEON_PUSH_DATABASE_URL;
 if(!uri)throw new Error('Dedicated push database connection missing');
 let parsed:URL;
 try{parsed=new URL(uri)}catch{throw new Error('Invalid private push database connection')}
 if(!['postgres:','postgresql:'].includes(parsed.protocol)||
   decodeURIComponent(parsed.username)!=='coroinhas_push_worker'||
   !parsed.password||!parsed.hostname.endsWith('.neon.tech')||
   parsed.pathname!=='/coroinhas'||parsed.searchParams.get('sslmode')!=='require')
   throw new Error('Push connection must use the restricted Neon role over TLS');
 pool??=new Pool({connectionString:uri,max:1,connectionTimeoutMillis:5000,idleTimeoutMillis:10000});
 webpush.setVapidDetails(subject()!,publicKey()!,privateKey()!);
 return dispatchPushBatch({query:(sql,values)=>pool!.query(sql,values)} as PushDatabase,
   claim=>webpush.sendNotification(
     {endpoint:claim.endpoint,keys:{p256dh:claim.p256dh,auth:claim.auth}},
     JSON.stringify({title:claim.title,body:claim.body,tag:claim.notification_id}),
     {TTL:3600,timeout:7000}
   ),limit);
}
