import {createNeonAuth} from '@neon/auth/next/server';
let auth:ReturnType<typeof createNeonAuth>|undefined;
export const migrationEnabled=()=>process.env.NEON_MIGRATION_ENABLED==='true'&&process.env.NEXT_PUBLIC_DATA_BACKEND==='neon-migration'&&process.env.VERCEL_ENV!=='production';
export function getNeonAuth(){
 if(!migrationEnabled()||!process.env.NEON_AUTH_BASE_URL||!process.env.NEON_AUTH_COOKIE_SECRET)throw new Error('Authentication unavailable');
 return auth??=createNeonAuth({baseUrl:process.env.NEON_AUTH_BASE_URL,cookies:{secret:process.env.NEON_AUTH_COOKIE_SECRET,sessionDataTtl:30}});
}
