import {NextRequest,NextResponse} from 'next/server';
import {getNeonAuth,migrationEnabled} from '@/lib/auth/server';
import {getPool} from '@/lib/neon/database';
export const runtime='nodejs';
export async function POST(req:NextRequest){
 if(!migrationEnabled())return NextResponse.json({message:'Desativado'},{status:404});
 if(req.headers.get('origin')!==req.nextUrl.origin)return NextResponse.json({message:'Origem inválida'},{status:403});
 try{
  const {data}=await getNeonAuth().getSession();
  if(!data?.user||!data.session)return NextResponse.json({message:'Entre na sua conta.'},{status:401});
  const body=await req.json();
  const role=body.requestedRole==='pai'?'pai':'coroinha';
  const result=await getPool().query('SELECT migration_private.resolve_neon_identity($1::uuid,$2::uuid,$3::text) AS profile_id',[data.user.id,data.session.id,role]);
  return NextResponse.json({profileId:result.rows[0].profile_id},{headers:{'Cache-Control':'no-store'}});
 }catch{return NextResponse.json({message:'Não foi possível vincular esta conta. Se você já possuía cadastro, solicite a vinculação segura ao responsável. Nenhum código de confirmação é necessário.'},{status:403,headers:{'Cache-Control':'no-store'}})}
}
