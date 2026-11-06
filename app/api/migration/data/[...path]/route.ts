import {NextRequest,NextResponse} from 'next/server';
import {Pool} from 'pg';
import {createClient} from '@supabase/supabase-js';
import {compileQuery,QueryError} from '@/lib/neon/query';
export const runtime='nodejs';
export const dynamic='force-dynamic';
let pool:Pool|undefined;
function error(message:string,status:number,code='MIGRATION_ERROR'){
 return NextResponse.json({message,code,details:null,hint:null},{status,headers:{'Cache-Control':'no-store'}});
}
async function handle(req:NextRequest,context:{params:Promise<{path:string[]}>}) {
 // Deliberately impossible to turn on in a production Vercel deployment.
 if(process.env.NEON_MIGRATION_ENABLED!=='true'||process.env.VERCEL_ENV==='production')return error('Ambiente de migração desativado.',404);
 const databaseUrl=process.env.NEON_MIGRATION_DATABASE_URL;
 const authUrl=process.env.NEXT_PUBLIC_SUPABASE_URL;
 const authKey=process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
 if(!databaseUrl||!authUrl||!authKey)return error('Ambiente de migração incompleto.',503);
 const authorization=req.headers.get('authorization')||'';
 if(!authorization.startsWith('Bearer ')||authorization.length>8192)return error('Não autenticado.',401);
 const auth=createClient(authUrl,authKey,{auth:{persistSession:false,autoRefreshToken:false}});
 // getUser validates with the identity provider; never trust a decoded client JWT.
 let user;
 try{const result=await auth.auth.getUser(authorization.slice(7));if(result.error||!result.data.user)return error('Sessão inválida.',401);user=result.data.user}catch{return error('Não foi possível validar a sessão.',503)}
 if(!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(user.id))return error('Identidade inválida.',401);
 let query;
 try{
  const raw=['GET','DELETE'].includes(req.method)?'{}':await req.text();
  if(raw.length>65536)return error('Requisição muito grande.',413);
  query=compileQuery((await context.params).path,req.method,req.nextUrl.searchParams,JSON.parse(raw||'{}'),req.headers.get('prefer')||'');
 }catch{return error('Operação não suportada no ambiente de migração.',400)}
 pool??=new Pool({connectionString:databaseUrl,max:3,idleTimeoutMillis:10000,connectionTimeoutMillis:10000});
 let client;
 try {
  client=await pool.connect();await client.query('BEGIN');
  await client.query("SET LOCAL statement_timeout='8s'");
  const marker=await client.query('SELECT branch_id FROM migration_private.environment WHERE id=true');
  if(marker.rows[0]?.branch_id!=='br-rough-hill-bcj6lzt1')throw new QueryError('Banco fora do ambiente isolado.');
  const identity=await client.query("SELECT profile_id FROM migration_private.identity_map WHERE provider='supabase' AND subject=$1",[user.id]);
  if(identity.rows[0]?.profile_id!==user.id){await client.query('ROLLBACK');return error('Conta ainda não sincronizada para homologação.',403)}
  await client.query("SELECT set_config('app.user_id',$1,true)",[user.id]);
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
  // Avoid returning SQL, connection details, or server error payloads.
  return error(code==='42501'?'Acesso negado.':'Operação não concluída na homologação.',code==='42501'?403:400);
 }finally{client?.release()}
}
export {handle as GET,handle as POST,handle as PATCH,handle as DELETE};
