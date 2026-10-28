import {NextRequest,NextResponse} from 'next/server';
import webpush from 'web-push';
import {createClient} from '@supabase/supabase-js';
export const runtime='nodejs';
export async function POST(req:NextRequest){
 const secret=process.env.PUSH_WEBHOOK_SECRET;
 if(!secret||req.headers.get('x-push-secret')!==secret)return NextResponse.json({error:'Unauthorized'},{status:401});
 const {notification_id}=await req.json();
 if(typeof notification_id!=='string'||!/^[0-9a-f-]{36}$/i.test(notification_id))return NextResponse.json({error:'Invalid ID'},{status:400});
 const vapidKey=process.env.VAPID_PRIVATE_KEY;
 if(!vapidKey)return NextResponse.json({error:'Push not configured'},{status:503});
 const client=createClient(process.env.NEXT_PUBLIC_SUPABASE_URL||'https://dsglwwwwdtjynipauvrp.supabase.co',process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY||'',{auth:{persistSession:false}});
 const {data,error}=await client.rpc('get_push_targets',{p_secret:secret,p_notification_id:notification_id});
 if(error)return NextResponse.json({error:'Cannot get recipients'},{status:500});
 webpush.setVapidDetails('mailto:lsantana.contato@hotmail.com','BDov9q_DBJrHGsmcCsMSIgkXnrWFYWioUSaD77Cajavor6dQxNINg2wXjMC8EmHjg79rPZByvl_1ynRPZk2EBGI',vapidKey);
 const outcomes=await Promise.allSettled((data||[]).map((row:{endpoint:string;p256dh:string;auth:string;title:string;body:string})=>webpush.sendNotification({endpoint:row.endpoint,keys:{p256dh:row.p256dh,auth:row.auth}},JSON.stringify({title:row.title,body:row.body}),{TTL:3600})));
 return NextResponse.json({processed:outcomes.length,sent:outcomes.filter(o=>o.status==='fulfilled').length});
}
