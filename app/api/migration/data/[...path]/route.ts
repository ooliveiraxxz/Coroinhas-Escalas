import {NextRequest,NextResponse} from 'next/server';
import {getNeonAuth,migrationEnabled} from '@/lib/auth/server';
import {getPool} from '@/lib/neon/database';
import {compileQuery} from '@/lib/neon/query';
export const runtime='nodejs';
export const dynamic='force-dynamic';

function error(message:string,status:number,code='MIGRATION_ERROR'){
 return NextResponse.json({message,code,details:null,hint:null},{status,headers:{'Cache-Control':'no-store'}});
}
async function handle(req:NextRequest,context:{params:Promise<{path:string[]}>}) {
 // Deliberately impossible to turn on in a production Vercel deployment.
 if(!migrationEnabled())return error('Ambiente de migração desativado.',404);
 if(!process.env.NEON_MIGRATION_DATABASE_URL||!process.env.NEON_AUTH_BASE_URL||!process.env.NEON_AUTH_COOKIE_SECRET)return error('Ambiente de migração incompleto.',503);
 if(req.method!=='GET'&&req.headers.get('origin')!==req.nextUrl.origin)return error('Origem inválida.',403);
 const length=req.headers.get('content-length');
 if(length!==null&&(!/^\d+$/.test(length)||Number(length)>65536))
  return error('Requisição muito grande.',413);
 if(!req.headers.get('cookie'))return error('Não autenticado.',401);
 let session;
 try{const result=await getNeonAuth().getSession();session=result.data;if(!session?.user||!session.session)return error('Não autenticado.',401)}catch{return error('Sessão inválida.',401)}
 let query;
 try{
  const raw=['GET','DELETE'].includes(req.method)?'{}':await req.text();
  if(raw.length>65536)return error('Requisição muito grande.',413);
  query=compileQuery((await context.params).path,req.method,req.nextUrl.searchParams,JSON.parse(raw||'{}'),req.headers.get('prefer')||'');
 }catch{return error('Operação não suportada no ambiente de migração.',400)}
 let client;
 try {
  client=await getPool().connect();await client.query('BEGIN');
  await client.query("SET LOCAL statement_timeout='8s'");
  const identity=await client.query('SELECT migration_private.resolve_neon_identity($1::uuid,$2::uuid,NULL) AS profile_id',[session.user.id,session.session.id]);
  await client.query("SELECT set_config('app.user_id',$1,true)",[identity.rows[0].profile_id]);
  await client.query('SET LOCAL ROLE coroinhas_app');
  const result=await client.query(query.text,query.values);
  const singular=req.headers.get('accept')?.includes('application/vnd.pgrst.object+json');
  if(singular&&!query.rpc&&result.rows.length!==1){await client.query('ROLLBACK');return error(`JSON object requested, ${result.rows.length} rows returned`,406,'PGRST116')}
  await client.query('COMMIT');
  if(!query.returning)return new NextResponse(null,{status:204,headers:{'Cache-Control':'no-store'}});
  return NextResponse.json(query.rpc?result.rows[0]?.result??null:singular?result.rows[0]:result.rows,{headers:{'Cache-Control':'no-store'}});
 }catch(e){
  if(client)await client.query('ROLLBACK').catch(()=>{});
  const code=typeof e==='object'&&e!==null&&'code'in e?String(e.code):'';
  // Mensagens de domínio explicitamente permitidas; nunca exponha SQL, detalhes de conexão ou erros internos.
  const detail=typeof e==='object'&&e!==null&&'message' in e?String(e.message):'';
  if(code==='42501')return error('Acesso negado.',403);
  if(code==='P0001'&&detail==='Nenhum destinatario encontrado')return error('Não há coroinhas aprovados para receber esta notificação.',422,'NO_RECIPIENTS');
  if(code==='P0001'&&detail==='Nenhum destinatário aprovado encontrado para o grupo selecionado.')return error(detail,422,'NO_RECIPIENTS');
  return error('Não foi possível concluir a operação. Tente novamente.',400);
 }finally{client?.release()}
}
export {handle as GET,handle as POST,handle as PATCH,handle as DELETE};
