import {NextRequest,NextResponse} from 'next/server';
import {getNeonAuth,migrationEnabled} from '@/lib/auth/server';
import {getPool} from '@/lib/neon/database';

export const runtime='nodejs';
export const dynamic='force-dynamic';
const reply=(body:unknown,status=200)=>NextResponse.json(body,{status,headers:{'Cache-Control':'private, no-store'}});

export async function GET(req:NextRequest){
 if(!migrationEnabled())return reply({connected:false,issues:[],reason:'Banco indisponível.'},503);
 if(!req.headers.get('cookie'))return reply({connected:false,issues:[],reason:'Não autenticado.'},401);
 let session;
 try{
  const result=await getNeonAuth().getSession();session=result.data;
  if(!session?.user||!session.session)return reply({connected:false,issues:[],reason:'Não autenticado.'},401);
 }catch{return reply({connected:false,issues:[],reason:'Sessão inválida.'},401)}
 let client;
 try{
  client=await getPool().connect();
  await client.query('BEGIN');
  await client.query("SET LOCAL statement_timeout='5s'");
  const identity=await client.query('SELECT migration_private.resolve_neon_identity($1::uuid,$2::uuid,NULL) AS profile_id',[session.user.id,session.session.id]);
  await client.query("SELECT set_config('app.user_id',$1,true)",[identity.rows[0].profile_id]);
  await client.query('SET LOCAL ROLE coroinhas_app');
  const role=await client.query('SELECT public.is_developer() AS allowed');
  await client.query('ROLLBACK');
  if(!role.rows[0]?.allowed)return reply({connected:false,issues:[],reason:'Acesso restrito ao Desenvolvedor.'},403);
 }catch{
  if(client)await client.query('ROLLBACK').catch(()=>{});
  return reply({connected:false,issues:[],reason:'Permissão não confirmada.'},403);
 }finally{client?.release()}
 const token=process.env.VERCEL_READ_TOKEN;
 if(!token)return reply({connected:false,issues:[],reason:'Falta configurar VERCEL_READ_TOKEN na Vercel.'});
 try{
  const params=new URLSearchParams({projectId:'coroinhas-escalas',limit:'30'});
  if(process.env.VERCEL_TEAM_ID)params.set('teamId',process.env.VERCEL_TEAM_ID);
  const response=await fetch('https://api.vercel.com/v6/deployments?'+params.toString(),{
   headers:{Authorization:'Bearer '+token},cache:'no-store',signal:AbortSignal.timeout(6500)
  });
  if(!response.ok)return reply({connected:false,issues:[],reason:'Token ou permissões da Vercel não autorizados.'});
  const result=await response.json() as {deployments?:Array<{uid?:string;id?:string;name?:string;url?:string;state?:string;created?:number;meta?:{githubCommitMessage?:string}}>};
  const issues=(result.deployments||[]).filter(d=>d.state==='ERROR'||d.state==='CANCELED').map(d=>({
   id:String(d.uid||d.id||''),title:d.meta?.githubCommitMessage||'Publicação com problema',
   state:d.state==='ERROR'?'Falha na publicação':'Publicação cancelada',
   updated_at:new Date(d.created||Date.now()).toISOString(),
   url:d.url?'https://'+d.url:'https://vercel.com'
  }));
  return reply({connected:true,issues,checked_at:new Date().toISOString()});
 }catch{return reply({connected:false,issues:[],reason:'Não foi possível consultar as publicações da Vercel.'})}
}
