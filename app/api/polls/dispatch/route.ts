import {NextRequest,NextResponse} from 'next/server';
import {getPool} from '@/lib/neon/database';
import {migrationEnabled} from '@/lib/auth/server';

export const runtime='nodejs';
export const dynamic='force-dynamic';

export async function GET(req:NextRequest){
 const secret=process.env.CRON_SECRET;
 if(!secret||req.headers.get('authorization')!==`Bearer ${secret}`)
  return NextResponse.json({error:'Acesso não autorizado'},{status:401});
 if(!migrationEnabled())return NextResponse.json({error:'Banco indisponível'},{status:503});
 try{
  const result=await getPool().query('SELECT public.poll_dispatch() AS result');
  return NextResponse.json({ok:true,processed:result.rows[0]?.result??null},{headers:{'Cache-Control':'no-store'}});
 }catch{
  return NextResponse.json({error:'Falha ao processar enquetes programadas'},{status:500});
 }
}
