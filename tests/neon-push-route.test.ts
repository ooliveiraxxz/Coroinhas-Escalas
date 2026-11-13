import test from 'node:test';
import assert from 'node:assert/strict';
import {NextRequest} from 'next/server';
import {GET} from '../app/api/push/neon-dispatch/route';

test('Neon push dispatcher remains disabled on preview even with tempting flags',async()=>{
 const keys=['NEON_MIGRATION_ENABLED','NEXT_PUBLIC_DATA_BACKEND',
  'VERCEL_ENV','NEON_PUSH_DISPATCH_ENABLED',
  'NEON_PRODUCTION_CUTOVER_ENABLED','NEON_PRODUCTION_APPROVED_COMMIT','VERCEL_GIT_COMMIT_SHA'];
 const previous=Object.fromEntries(keys.map(k=>[k,process.env[k]]));
 try{
  Object.assign(process.env,{
   NEON_MIGRATION_ENABLED:'true',NEXT_PUBLIC_DATA_BACKEND:'neon-migration',
   VERCEL_ENV:'preview',NEON_PUSH_DISPATCH_ENABLED:'true'
  });
  const req=new NextRequest('https://example.invalid/api/push/neon-dispatch');
  const reply=await GET(req);
  assert.equal(reply.status,404);
  assert.equal(reply.headers.get('Cache-Control'),'no-store');

  process.env.VERCEL_ENV='production';
  delete process.env.NEON_PRODUCTION_CUTOVER_ENABLED;
  assert.equal((await GET(req)).status,404);
  process.env.NEON_PRODUCTION_CUTOVER_ENABLED='true';
  process.env.NEON_PRODUCTION_APPROVED_COMMIT='b'.repeat(40);
  process.env.VERCEL_GIT_COMMIT_SHA='a'.repeat(40);
  // Persistent approved cutover is no longer tied to the deploying commit SHA.
  // Without CRON_SECRET authentication, a production dispatcher must still deny access.
  assert.equal((await GET(req)).status,401);
 }finally{
  for(const [key,value] of Object.entries(previous)){
   if(value===undefined)delete process.env[key];else process.env[key]=value;
  }
 }
});
