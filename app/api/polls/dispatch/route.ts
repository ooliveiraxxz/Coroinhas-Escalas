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
  const pool=getPool();
  const polls=await pool.query('SELECT public.poll_dispatch() AS result');
  const approvals=await pool.query('SELECT public.run_pending_auto_approvals() AS count');
  const archive=await pool.query('SELECT public.archive_maintenance() AS result');
  // A daily, bounded snapshot supports storage-growth trends without affecting the poll schedule.
  try{await pool.query('SELECT public.system_health_capture()')}catch{console.warn('Neon health snapshot unavailable')}
  let push:Record<string,number>|{error:string}={processed:0,sent:0,failed:0,skipped:0};
  try{
   const {dispatchNeonPush}=await import('@/lib/neon/push-runtime');
   push=await dispatchNeonPush(20);
  }catch{push={error:'O processamento push será retomado na próxima chamada'};}
  return NextResponse.json(
   {ok:true,processed:polls.rows[0]?.result??null,autoApprovals:approvals.rows[0]?.count??0,archive:archive.rows[0]?.result??null,push},
   {headers:{'Cache-Control':'no-store'}}
  );
 }catch{
  return NextResponse.json({error:'Falha ao processar rotinas programadas'},{status:500});
 }
}
