import test from 'node:test';
import assert from 'node:assert/strict';
import {NextRequest} from 'next/server';
import {GET} from '../app/api/migration/data/[...path]/route';
import {POST as sessionPOST} from '../app/api/migration/session/route';
import {migrationEnabled} from '../lib/auth/server';
const req=()=>new NextRequest('http://localhost/api/migration/data/profiles');
const context={params:Promise.resolve({path:['profiles']})};
test('migration endpoint defaults to disabled and cannot be enabled in production',async()=>{
 delete process.env.NEON_MIGRATION_ENABLED;
 assert.equal((await GET(req(),context)).status,404);
 process.env.NEON_MIGRATION_ENABLED='true';process.env.VERCEL_ENV='production';
 assert.equal((await GET(req(),context)).status,404);
 delete process.env.VERCEL_ENV;delete process.env.NEON_MIGRATION_ENABLED;
});
test('production Neon activation requires explicit server-side cutover flag',()=>{
 const keys=['NEON_MIGRATION_ENABLED','NEXT_PUBLIC_DATA_BACKEND','VERCEL_ENV','NEON_PRODUCTION_CUTOVER_ENABLED','NEON_PRODUCTION_APPROVED_COMMIT','VERCEL_GIT_COMMIT_SHA'];
 const old=Object.fromEntries(keys.map(k=>[k,process.env[k]]));
 try{
  Object.assign(process.env,{NEON_MIGRATION_ENABLED:'true',NEXT_PUBLIC_DATA_BACKEND:'neon-migration',VERCEL_ENV:'production',VERCEL_GIT_COMMIT_SHA:'a'.repeat(40)});
  delete process.env.NEON_PRODUCTION_CUTOVER_ENABLED;
  delete process.env.NEON_PRODUCTION_APPROVED_COMMIT;
  assert.equal(migrationEnabled(),false);
  process.env.NEON_PRODUCTION_CUTOVER_ENABLED='false';
  assert.equal(migrationEnabled(),false);
  process.env.NEON_PRODUCTION_CUTOVER_ENABLED='true';
  assert.equal(migrationEnabled(),true);
  // Approved cutover is persistent across later deploy SHAs; it no longer relies on SHA equality.
  process.env.NEON_PRODUCTION_APPROVED_COMMIT='b'.repeat(40);
  assert.equal(migrationEnabled(),true);
  process.env.NEON_MIGRATION_ENABLED='false';
  assert.equal(migrationEnabled(),false);
  process.env.NEON_MIGRATION_ENABLED='true';
  process.env.NEXT_PUBLIC_DATA_BACKEND='supabase';
  assert.equal(migrationEnabled(),false);
 }finally{
  for(const [k,v] of Object.entries(old)){if(v===undefined)delete process.env[k];else process.env[k]=v}
 }
});
test('missing environment and missing token fail before any database connection',async()=>{
 process.env.NEON_MIGRATION_ENABLED='true';process.env.NEXT_PUBLIC_DATA_BACKEND='neon-migration';
 assert.equal((await GET(req(),context)).status,503);
 process.env.NEON_MIGRATION_DATABASE_URL='postgres://invalid.example/test';
 process.env.NEON_AUTH_BASE_URL='https://example.invalid';
 process.env.NEON_AUTH_COOKIE_SECRET='test-secret-at-least-32-characters-long';
 process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY='test';
 assert.equal((await GET(req(),context)).status,401);
 for(const k of ['NEON_MIGRATION_ENABLED','NEON_MIGRATION_DATABASE_URL','NEON_AUTH_BASE_URL','NEON_AUTH_COOKIE_SECRET','NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY','NEXT_PUBLIC_DATA_BACKEND'])delete process.env[k];
});

test('session provisioning refuses cross-origin requests and unsupported payloads before touching auth or database',async()=>{
 process.env.NEON_MIGRATION_ENABLED='true';
 process.env.NEXT_PUBLIC_DATA_BACKEND='neon-migration';
 delete process.env.VERCEL_ENV;
 const req=(body:string,headers:Record<string,string>={})=>new NextRequest('http://localhost/api/migration/session',{
  method:'POST',headers:{origin:'http://localhost','content-type':'application/json',...headers},body
 });
 try{
  assert.equal((await sessionPOST(req('{}',{origin:'https://another.example'}))).status,403);
  assert.equal((await sessionPOST(req('{}',{'content-type':'text/plain'}))).status,415);
  assert.equal((await sessionPOST(req('x'))).status,400);
  assert.equal((await sessionPOST(req(JSON.stringify({requestedRole:'desenvolvedor'})))).status,400);
  assert.equal((await sessionPOST(req(JSON.stringify({requestedRole:'coordenadora'})))).status,400);
  assert.equal((await sessionPOST(req(JSON.stringify({requestedRole:'pai',isAdmin:true})))).status,400);
  assert.equal((await sessionPOST(req(JSON.stringify([{}])))).status,400);
  assert.equal((await sessionPOST(req(JSON.stringify({requestedRole:'coroinha',pad:'x'.repeat(1100)})))).status,413);
  const denied=await sessionPOST(req('{"requestedRole":"coroinha"}',{origin:'https://another.example'}));
  assert.equal(denied.headers.get('cache-control'),'no-store');
 }finally{
  delete process.env.NEON_MIGRATION_ENABLED;
  delete process.env.NEXT_PUBLIC_DATA_BACKEND;
 }
});

test('migration API rejects malformed or huge Content-Length before invoking auth/database',async()=>{
 process.env.NEON_MIGRATION_ENABLED='true';
 process.env.NEXT_PUBLIC_DATA_BACKEND='neon-migration';
 process.env.NEON_MIGRATION_DATABASE_URL='postgresql://coroinhas_gateway:placeholder@ep-test.neon.tech/coroinhas';
 process.env.NEON_AUTH_BASE_URL='https://example.invalid';
 process.env.NEON_AUTH_COOKIE_SECRET='test-secret-at-least-32-characters-long';
 const input=(length:string)=>new NextRequest('http://localhost/api/migration/data/masses',{
  method:'POST',
  headers:{origin:'http://localhost',cookie:'s=fake','content-length':length,
   'content-type':'application/json'},
  body:'{}'
 });
 try{
  assert.equal((await (await import('../app/api/migration/data/[...path]/route')).POST(input('999999'),context)).status,413);
  assert.equal((await (await import('../app/api/migration/data/[...path]/route')).POST(input('not-a-number'),context)).status,413);
  for(const length of ['0','2','65536']){
   const valid=input(length);valid.headers.delete('cookie');
   assert.equal((await (await import('../app/api/migration/data/[...path]/route')).POST(valid,context)).status,401);
  }
 }finally{
  for(const k of ['NEON_MIGRATION_ENABLED','NEXT_PUBLIC_DATA_BACKEND','NEON_MIGRATION_DATABASE_URL',
   'NEON_AUTH_BASE_URL','NEON_AUTH_COOKIE_SECRET'])delete process.env[k];
 }
});
