import {NextRequest,NextResponse} from 'next/server';
import {getPool} from '@/lib/neon/database';
export const runtime='nodejs';
export const dynamic='force-dynamic';
// Called by Vercel Cron with Authorization: Bearer <CRON_SECRET>.
export async function GET(req:NextRequest){
 const secret=process.env.CRON_SECRET;
 if(!secret||req.headers.get('authorization')!==`Bearer ${secret}`)
  return NextResponse.json({error:'Não autorizado'},{status:401});
 if(!process.env.NEON_MIGRATION_DATABASE_URL)
  return NextResponse.json({error:'Banco não configurado'},{status:503});
 try{
  const result=await getPool().query('SELECT public.run_pending_auto_approvals() AS approved');
  return NextResponse.json({approved:result.rows[0]?.approved??0},{headers:{'Cache-Control':'no-store'}});
 }catch{
  return NextResponse.json({error:'Falha ao processar solicitações'},{status:500});
 }
}