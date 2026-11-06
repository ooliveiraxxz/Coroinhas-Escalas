import {NextRequest,NextResponse} from 'next/server';
import {getNeonAuth,migrationEnabled} from '@/lib/auth/server';
export const runtime='nodejs';
async function handle(req:NextRequest,context:{params:Promise<{path:string[]}>}){
 if(!migrationEnabled())return NextResponse.json({message:'Homologação desativada'},{status:404});
 try{
  const handlers=getNeonAuth().handler();
  const method=req.method as keyof typeof handlers;
  return await handlers[method](req,context);
 }catch{return NextResponse.json({message:'Não foi possível concluir a autenticação.'},{status:503})}
}
export {handle as GET,handle as POST,handle as PUT,handle as PATCH,handle as DELETE};
