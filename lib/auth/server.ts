import {createNeonAuth} from '@neon/auth/next/server';

let auth:ReturnType<typeof createNeonAuth>|undefined;

// O Neon só opera quando o backend estiver selecionado e habilitado.
// Após o corte aprovado, futuras atualizações de código não podem desligar
// automaticamente o cadastro e o login ao mudar o SHA do deploy.
// A chave privada NEON_PRODUCTION_CUTOVER_ENABLED continua sendo o controle
// explícito e independente da seleção pública do backend.
export function migrationEnabled(){
 if(process.env.NEON_MIGRATION_ENABLED!=='true'||
    process.env.NEXT_PUBLIC_DATA_BACKEND!=='neon-migration')return false;
 if(process.env.VERCEL_ENV!=='production')return true;
 return process.env.NEON_PRODUCTION_CUTOVER_ENABLED==='true';
}

export function getNeonAuth(){
 if(!migrationEnabled()||!process.env.NEON_AUTH_BASE_URL||!process.env.NEON_AUTH_COOKIE_SECRET)
  throw new Error('Authentication unavailable');
 return auth??=createNeonAuth({
  baseUrl:process.env.NEON_AUTH_BASE_URL,
  cookies:{secret:process.env.NEON_AUTH_COOKIE_SECRET,sessionDataTtl:30}
 });
}
