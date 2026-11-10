import {NextRequest,NextResponse} from 'next/server';
import {getNeonAuth,migrationEnabled} from '@/lib/auth/server';
import {getPool} from '@/lib/neon/database';
export const runtime='nodejs';

// Session establishment can create a pending profile. Reject malformed input
// before reaching the identity resolver, even for authenticated requests.
function response(message:string,status:number){
 return NextResponse.json({message},{status,headers:{'Cache-Control':'no-store'}});
}
export async function POST(req:NextRequest){
 if(!migrationEnabled())return response('Desativado',404);
 if(req.headers.get('origin')!==req.nextUrl.origin)return response('Origem inválida',403);
 const type=req.headers.get('content-type')||'';
 if(!/^application\/json(?:\s*;|\s*$)/i.test(type))return response('Formato inválido',415);
 let body:unknown;
 try{
  const raw=await req.text();
  if(raw.length>1024)return response('Requisição muito grande',413);
  body=JSON.parse(raw);
 }catch{return response('JSON inválido',400)}
 if(!body||typeof body!=='object'||Array.isArray(body))return response('Dados inválidos',400);
 const fields=Object.keys(body);
 if(fields.some(field=>field!=='requestedRole'))return response('Campos não permitidos',400);
 const requestedRole=(body as {requestedRole?:unknown}).requestedRole;
 if(requestedRole!==undefined&&requestedRole!==null&&requestedRole!=='pai'&&requestedRole!=='coroinha'&&requestedRole!=='cerimoniario')
  return response('Tipo de cadastro inválido',400);
 try{
  const {data}=await getNeonAuth().getSession();
  if(!data?.user||!data.session)return response('Entre na sua conta.',401);
  const role=requestedRole??null;
  const result=await getPool().query(
   'SELECT migration_private.resolve_neon_identity($1::uuid,$2::uuid,$3::text) AS profile_id',
   [data.user.id,data.session.id,role]
  );
  return NextResponse.json({profileId:result.rows[0].profile_id},{headers:{'Cache-Control':'no-store'}});
 }catch{
  return response('Não foi possível vincular esta conta. Se você já possuía cadastro, solicite a vinculação segura ao responsável. Nenhum código de confirmação é necessário.',403);
 }
}
