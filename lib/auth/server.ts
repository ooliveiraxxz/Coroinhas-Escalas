import {createNeonAuth} from '@neon/auth/next/server';

let auth:ReturnType<typeof createNeonAuth>|undefined;
const shaPattern=/^[0-9a-f]{40}$/i;

// Production is ALWAYS disabled by default. The cutover operator must explicitly
// enable it AND pin the exact reviewed deployment SHA; merely changing the public
// backend selector cannot activate Neon against real users.
export function migrationEnabled(){
 if(process.env.NEON_MIGRATION_ENABLED!=='true'||
    process.env.NEXT_PUBLIC_DATA_BACKEND!=='neon-migration')return false;
 if(process.env.VERCEL_ENV!=='production')return true;
 const approved=process.env.NEON_PRODUCTION_APPROVED_COMMIT||'';
 const deployed=process.env.VERCEL_GIT_COMMIT_SHA||'';
 return process.env.NEON_PRODUCTION_CUTOVER_ENABLED==='true'&&
  shaPattern.test(approved)&&approved===deployed;
}

export function getNeonAuth(){
 if(!migrationEnabled()||!process.env.NEON_AUTH_BASE_URL||!process.env.NEON_AUTH_COOKIE_SECRET)
  throw new Error('Authentication unavailable');
 return auth??=createNeonAuth({
  baseUrl:process.env.NEON_AUTH_BASE_URL,
  cookies:{secret:process.env.NEON_AUTH_COOKIE_SECRET,sessionDataTtl:30}
 });
}
