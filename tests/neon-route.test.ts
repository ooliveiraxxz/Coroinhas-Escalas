import test from 'node:test';
import assert from 'node:assert/strict';
import {NextRequest} from 'next/server';
import {GET} from '../app/api/migration/data/[...path]/route';
import {POST as sessionPOST} from '../app/api/migration/session/route';
const req=()=>new NextRequest('http://localhost/api/migration/data/profiles');
const context={params:Promise.resolve({path:['profiles']})};
test('migration endpoint defaults to disabled and cannot be enabled in production',async()=>{
 delete process.env.NEON_MIGRATION_ENABLED;
 assert.equal((await GET(req(),context)).status,404);
 process.env.NEON_MIGRATION_ENABLED='true';process.env.VERCEL_ENV='production';
 assert.equal((await GET(req(),context)).status,404);
 delete process.env.VERCEL_ENV;delete process.env.NEON_MIGRATION_ENABLED;
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
