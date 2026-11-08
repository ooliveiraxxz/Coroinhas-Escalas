import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

// Exercise the actual CLI orchestration without credentials or network writes.
async function runSync(apply=false, extraRows=false, stale=false, branch='br-rough-hill-bcj6lzt1', tombstoneFixture=false){
 const plan=apply?JSON.parse((await runSync()).output[0]):null;
 if(stale)plan.fingerprints[0].targetChecksum='changed';
 const calls:{side:string;sql:string}[]=[];
 const output:string[]=[];
 const proc={argv:apply?['--apply','--confirm-isolated-neon','--reviewed-plan=/reviewed.json']:[],env:{SOURCE_READONLY_DATABASE_URL:'postgresql://reader:fixture@db.dsglwwwwdtjynipauvrp.supabase.co/postgres',NEON_MIGRATION_ADMIN_DATABASE_URL:'postgresql://coroinhas_owner:fixture@fixture.neon.tech/coroinhas',MIGRATION_SOURCE_PROJECT:'dsglwwwwdtjynipauvrp',MIGRATION_TARGET_BRANCH_ID:branch},exitCode:0};
 class Client{
  side:string;
  constructor({connectionString}:{connectionString:string}){this.side=connectionString.includes('supabase')?'source':'target'}
  async connect(){} async end(){}
  async query(sql:string){
   calls.push({side:this.side,sql});
   if(sql.includes('SELECT branch_id'))return {rows:[{branch_id:branch}]};
   if(tombstoneFixture&&sql.includes('SELECT count(*)::int n FROM public.audit_log'))return {rows:[{n:1}]};
   if(tombstoneFixture&&sql.includes('SELECT count(*)::int n FROM public.site_updates'))return {rows:[{n:0}]};
   if(tombstoneFixture&&sql.includes('site_update_conflict_archive'))return {rows:[{n:1}]};
   if(tombstoneFixture&&sql.includes('t.id<>$1'))return {rows:[{count:0,checksum:'empty'}]};
   if(sql.includes('WHERE NOT EXISTS'))return {rows:[{count:(extraRows||tombstoneFixture&&sql.includes('site_updates'))?1:0}]};
   if(sql.includes('to_jsonb(t) AS row'))return {rows:[],rowCount:0};
   if(sql.includes('checksum'))return {rows:[{count:tombstoneFixture&&this.side==='target'&&sql.includes('site_updates')?1:0,checksum:tombstoneFixture&&this.side==='target'&&sql.includes('site_updates')?'different':'empty'}]};
   return {rows:[],rowCount:0};
  }
 }
 const source=fs.readFileSync('migration/sync.mjs','utf8').replace(/^import .*;$/gm,'').replace('import.meta.url',JSON.stringify(new URL('../migration/sync.mjs',import.meta.url).href));
 await vm.runInNewContext(`(async()=>{${source}\n})()`,{fs:{...fs,readFileSync:(path:any,...args:any[])=>path==='/reviewed.json'?JSON.stringify(plan):(fs.readFileSync as any)(path,...args)},pg:{Client},URL,process:proc,console:{log:(s:string)=>output.push(s),error:(s:string)=>output.push(s)}});
 return {calls,output,proc};
}
test('sync default completes all 15 read-only comparisons without shadowing target connection',async()=>{
 const r=await runSync();assert.equal(r.proc.exitCode,0);assert.equal(JSON.parse(r.output[0]).tablesCompared,15);
 assert.ok(r.calls.filter(c=>c.side==='target').every(c=>/^(BEGIN READ ONLY|SELECT|ROLLBACK)/.test(c.sql)));
 assert.ok(r.calls.filter(c=>c.side==='source').every(c=>/^(BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY|SELECT|ROLLBACK)/.test(c.sql)));
});
test('sync explicitly confirmed apply completes and never writes source',async()=>{
 const r=await runSync(true);assert.equal(r.proc.exitCode,0);assert.equal(JSON.parse(r.output[0]).synced,true);
 assert.equal(r.calls.filter(c=>c.side==='target'&&c.sql.startsWith('INSERT INTO public.')).length,15);
 assert.ok(r.calls.filter(c=>c.side==='source').every(c=>/^(BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY|SELECT|ROLLBACK)/.test(c.sql)));
});
test('sync refuses destination-only rows before any write',async()=>{
 const r=await runSync(true,true);assert.equal(r.proc.exitCode,1);
 assert.ok(!r.calls.some(c=>/^(INSERT|ALTER|UPDATE|DELETE)/.test(c.sql)));
 assert.ok(r.calls.some(c=>c.side==='target'&&c.sql==='ROLLBACK'));
});

test('sync read-only reports destination-only fixtures without hiding the reconciliation plan',async()=>{
 const r=await runSync(false,true);assert.equal(r.proc.exitCode,0);
 const plan=JSON.parse(r.output[0]);
 assert.equal(plan.tablesCompared,15);
 assert.equal(plan.requiresConflictReview,true);
 assert.equal(plan.dataChecksMatch,false);
 assert.equal(plan.conflicts.length,15);
 assert.deepEqual(plan.conflicts[0],{table:'profiles',targetOnlyCount:1});
 assert.ok(r.calls.every(c=>/^(BEGIN|SELECT|ROLLBACK)/.test(c.sql)));
 assert.ok(!r.output[0].includes('fixture@'));
});

test('sync aborts a stale reviewed plan before any data mutation',async()=>{
 const r=await runSync(true,false,true);assert.equal(r.proc.exitCode,1);
 assert.ok(!r.calls.some(c=>/^(INSERT|ALTER|UPDATE|DELETE)/.test(c.sql)));
});

test('sync supports clean explicitly allowlisted isolated rehearsal branch without writes',async()=>{
 const r=await runSync(false,false,false,'br-odd-bread-bc1jxzsh');
 assert.equal(r.proc.exitCode,0);
 assert.equal(JSON.parse(r.output[0]).targetBranch,'br-odd-bread-bc1jxzsh');
 assert.ok(!r.calls.some(c=>/^(INSERT|ALTER|UPDATE|DELETE)/.test(c.sql)));
});
test('sync refuses unknown branch before attempting a database connection',async()=>{
 await assert.rejects(runSync(false,false,false,'br-unapproved-production'));
});

test('read-only sync reports audited source deletion as logical match without claiming physical identity',async()=>{
 const r=await runSync(false,false,false,'br-odd-bread-bc1jxzsh',true);
 assert.equal(r.proc.exitCode,0);
 const plan=JSON.parse(r.output[0]);
 assert.equal(plan.tablesCompared,15);
 assert.equal(plan.dataChecksMatch,false);
 assert.equal(plan.logicalDataChecksMatch,true);
 assert.equal(plan.reviewedTombstone.verified,true);
 assert.equal(plan.requiresConflictReview,true);
 assert.deepEqual(plan.conflicts,[{table:'site_updates',targetOnlyCount:1}]);
 assert.ok(r.calls.every(c=>/^(BEGIN|SELECT|ROLLBACK)/.test(c.sql)));
});
