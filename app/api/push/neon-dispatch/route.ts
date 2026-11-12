import {NextRequest,NextResponse} from 'next/server';
import {timingSafeEqual} from 'node:crypto';
import {migrationEnabled} from '@/lib/auth/server';
import {dispatchNeonPush} from '@/lib/neon/push-runtime';
export const runtime='nodejs';
export const dynamic='force-dynamic';

function authorized(actual:string|null,secret:string){
 if(!secret||!actual?.startsWith('Bearer '))return false;
 const first=Buffer.from(actual.slice(7),'utf8'),second=Buffer.from(secret,'utf8');
 return first.length===second.length&&timingSafeEqual(first,second);
}
export async function GET(req:NextRequest){
 if(!migrationEnabled()||process.env.VERCEL_ENV!=='production'||
    process.env.NEON_PUSH_DISPATCH_ENABLED!=='true')
  return NextResponse.json({message:'Serviço de notificações desativado'},{status:404,headers:{'Cache-Control':'no-store'}});
 if(!authorized(req.headers.get('authorization'),process.env.CRON_SECRET||''))
  return NextResponse.json({message:'Não autorizado'},{status:401,headers:{'Cache-Control':'no-store'}});
 try{
  const result=await dispatchNeonPush(20);
  return NextResponse.json(result,{headers:{'Cache-Control':'no-store'}});
 }catch{
  return NextResponse.json({message:'Falha controlada no processamento das notificações'},{status:503});
 }
}
