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
  return NextResponse.json(
   {ok:true,processed:polls.rows[0]?.result??null,autoApprovals:approvals.rows[0]?.count??0,archive:archive.rows[0]?.result??null},
   {headers:{'Cache-Control':'no-store'}}
  );
 }catch{
  return NextResponse.json({error:'Falha ao processar rotinas programadas'},{status:500});
 }
}
