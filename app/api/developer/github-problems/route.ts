import {NextRequest,NextResponse} from 'next/server';
import {getNeonAuth,migrationEnabled} from '@/lib/auth/server';
import {getPool} from '@/lib/neon/database';
export const runtime='nodejs';
export const dynamic='force-dynamic';
const noStore={'Cache-Control':'private, no-store'};
const reply=(body:unknown,status=200)=>NextResponse.json(body,{status,headers:noStore});
export async function GET(req:NextRequest){
 if(!migrationEnabled())return reply({reason:'Banco indisponível.',connected:false,issues:[]},503);
 if(!req.headers.get('cookie'))return reply({reason:'Não autenticado.',connected:false,issues:[]},401);
 let session;
 try{const result=await getNeonAuth().getSession();session=result.data;if(!session?.user||!session.session)return reply({reason:'Não autenticado.',connected:false,issues:[]},401)}
 catch{return reply({reason:'Sessão inválida.',connected:false,issues:[]},401)}
 const pool=getPool();
 const client=await pool.connect().catch(()=>null);
 if(!client)return reply({reason:'Neon indisponível.',connected:false,issues:[]},503);
 try{
  await client.query('BEGIN');
  await client.query("SET LOCAL statement_timeout='5s'");
  const identity=await client.query('SELECT migration_private.resolve_neon_identity($1::uuid,$2::uuid,NULL) AS profile_id',[session.user.id,session.session.id]);
  await client.query("SELECT set_config('app.user_id',$1,true)",[identity.rows[0].profile_id]);
  await client.query('SET LOCAL ROLE coroinhas_app');
  const role=await client.query("SELECT public.has_site_permission('view_developer_panel') AS allowed");
  await client.query('ROLLBACK');
  if(!role.rows[0]?.allowed)return reply({reason:'Sem permissão para visualizar o Painel do Desenvolvedor.',connected:false,issues:[]},403);
 }catch{
  await client.query('ROLLBACK').catch(()=>{});
  return reply({reason:'Não foi possível conferir a permissão.',connected:false,issues:[]},403);
 }finally{client.release()}
 // GitHub's API does not expose private repository issues or workflow failures anonymously.
 const token=process.env.GITHUB_READ_TOKEN;
 if(!token)return reply({connected:false,issues:[],reason:'Integração privada do GitHub pendente: falta configurar GITHUB_READ_TOKEN na Vercel.'});
 const headers={Authorization:`Bearer ${token}`,Accept:'application/vnd.github+json','X-GitHub-Api-Version':'2022-11-28'};
 const base='https://api.github.com/repos/ooliveiraxxz/Coroinhas-Escalas';
 try{
  const [issueResponse,actionResponse]=await Promise.all([
   fetch(base+'/issues?state=all&per_page=40&sort=updated&direction=desc',{headers,cache:'no-store',signal:AbortSignal.timeout(6500)}),
   fetch(base+'/actions/runs?status=failure&per_page=15',{headers,cache:'no-store',signal:AbortSignal.timeout(6500)})
  ]);
  if(!issueResponse.ok||!actionResponse.ok)return reply({connected:false,issues:[],reason:'Acesso ao GitHub indisponível. Confira o token de leitura e as permissões do repositório.'});
  const rawIssues=await issueResponse.json() as Array<Record<string,unknown>>;
  const actions=await actionResponse.json() as {workflow_runs?:Array<Record<string,unknown>>};
  const issues=[...rawIssues.filter(i=>!i.pull_request).map(i=>({
   id:Number(i.id),title:String(i.title||'Issue sem título'),url:String(i.html_url||''),
   state:String(i.state||'desconhecido'),updated_at:String(i.updated_at||''),
   kind:'Issue'
  })),...(actions.workflow_runs||[]).map(run=>({
   id:Number(run.id),title:'Workflow com falha: '+String(run.name||run.display_title||'Execução'),
   url:String(run.html_url||''),state:'falha',updated_at:String(run.updated_at||run.created_at||''),
   kind:'GitHub Actions'
  }))].sort((a,b)=>new Date(b.updated_at).getTime()-new Date(a.updated_at).getTime()).slice(0,50);
  return reply({connected:true,issues,checked_at:new Date().toISOString()});
 }catch{return reply({connected:false,issues:[],reason:'Falha temporária ao consultar o GitHub.'})}
}
