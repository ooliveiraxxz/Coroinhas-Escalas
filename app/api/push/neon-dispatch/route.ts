import {NextRequest,NextResponse} from 'next/server';
import {timingSafeEqual} from 'node:crypto';
import {Pool} from 'pg';
import webpush from 'web-push';
import {migrationEnabled} from '@/lib/auth/server';
import {dispatchPushBatch,type PushDatabase} from '@/lib/neon/push-dispatch';
export const runtime='nodejs';
export const dynamic='force-dynamic';

let pool:Pool|undefined;
function reply(data:Record<string,unknown>,status=200){
 return NextResponse.json(data,{status,headers:{'Cache-Control':'no-store'}});
}
function authorized(actual:string|null,secret:string){
 if(!secret||!actual?.startsWith('Bearer '))return false;
 const first=Buffer.from(actual.slice(7),'utf8'),second=Buffer.from(secret,'utf8');
 return first.length===second.length&&timingSafeEqual(first,second);
}
function pushDatabase(){
 const value=process.env.NEON_PUSH_DATABASE_URL;
 if(!value)throw new Error('Missing private push database connection');
 let url:URL;
 try{url=new URL(value)}catch{throw new Error('Invalid private push database connection')}
 if(!['postgres:','postgresql:'].includes(url.protocol)||
    decodeURIComponent(url.username)!=='coroinhas_push_worker'||
    !url.password||!url.hostname.endsWith('.neon.tech')||
    url.pathname!=='/coroinhas'||url.searchParams.get('sslmode')!=='require')
  throw new Error('Push connection must use the dedicated restricted Neon role over TLS');
 return pool??=new Pool({connectionString:value,max:1,
  connectionTimeoutMillis:5000,idleTimeoutMillis:10000});
}
export async function GET(req:NextRequest){
 // No push in preview or old Supabase production. This endpoint can only
 // be enabled AFTER the reviewed-commit cutover gate is activated.
 if(!migrationEnabled()||process.env.VERCEL_ENV!=='production'||
    process.env.NEON_PUSH_DISPATCH_ENABLED!=='true')
  return reply({message:'Serviço de notificações desativado'},404);
 if(!authorized(req.headers.get('authorization'),process.env.CRON_SECRET||''))
  return reply({message:'Não autorizado'},401);
 const publicKey=process.env.NEXT_PUBLIC_VAPID_PUBLIC_KEY;
 const privateKey=process.env.VAPID_PRIVATE_KEY;
 const subject=process.env.VAPID_SUBJECT;
 if(!publicKey||!privateKey||!subject)return reply({message:'Push não configurado'},503);
 try{
  webpush.setVapidDetails(subject,publicKey,privateKey);
  const db=pushDatabase();
  const result=await dispatchPushBatch(
   {query:(sql,values)=>db.query(sql,values)} as PushDatabase,
   claim=>webpush.sendNotification({
    endpoint:claim.endpoint,keys:{p256dh:claim.p256dh,auth:claim.auth}
   },JSON.stringify({title:claim.title,body:claim.body,tag:claim.notification_id}),
    {TTL:3600,timeout:10000}),
   10
  );
  return reply(result);
 }catch{
  // Never expose endpoints, VAPID keys, database error details or user content.
  return reply({message:'Falha controlada no processamento das notificações'},503);
 }
}
