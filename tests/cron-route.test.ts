import test from 'node:test';
import assert from 'node:assert/strict';
import {NextRequest} from 'next/server';
import {GET} from '../app/api/polls/dispatch/route';

// Route security checks must never reach a real database or dispatch notifications.
const keys=['CRON_SECRET','NEON_MIGRATION_ENABLED','NEXT_PUBLIC_DATA_BACKEND','VERCEL_ENV','NEON_MIGRATION_DATABASE_URL'];
async function isolated(run:()=>Promise<void>){
 const old=Object.fromEntries(keys.map(k=>[k,process.env[k]]));
 for(const k of keys)delete process.env[k];
 try{await run()}finally{for(const [k,v] of Object.entries(old)){if(v===undefined)delete process.env[k];else process.env[k]=v}}
}
const request=(authorization?:string)=>new NextRequest('https://qa.example.invalid/api/polls/dispatch',{
 headers:authorization?{authorization}:{},
});

test('cron refuses execution when server secret is absent',()=>isolated(async()=>{
 assert.equal((await GET(request('Bearer undefined'))).status,401);
}));
test('cron refuses requests without authentication',()=>isolated(async()=>{
 process.env.CRON_SECRET='qa-local-only';
 assert.equal((await GET(request())).status,401);
}));
test('cron refuses an incorrect bearer token',()=>isolated(async()=>{
 process.env.CRON_SECRET='qa-local-only';
 assert.equal((await GET(request('Bearer wrong'))).status,401);
}));
test('cron refuses execution when the backend is disabled',()=>isolated(async()=>{
 process.env.CRON_SECRET='qa-local-only';
 assert.equal((await GET(request('Bearer qa-local-only'))).status,503);
}));
test('cron contains configuration failures without leaking connection details',()=>isolated(async()=>{
 process.env.CRON_SECRET='qa-local-only';
 process.env.NEON_MIGRATION_ENABLED='true';
 process.env.NEXT_PUBLIC_DATA_BACKEND='neon-migration';
 const response=await GET(request('Bearer qa-local-only'));
 assert.equal(response.status,500);
 assert.deepEqual(await response.json(),{error:'Falha ao processar rotinas programadas'});
}));
