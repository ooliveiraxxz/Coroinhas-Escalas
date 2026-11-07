import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const notification='00000000-0000-4000-8000-000000000001',subscription='00000000-0000-4000-8000-000000000002';
async function dispatch({send=true,cancelled=false,claimed=true,status=0,approved=true}={}){
 let sends=0,reads=0;const updates:any[]=[];const output:string[]=[];
 const proc={argv:send?['--send-test']:[],env:{NEON_MIGRATION_ADMIN_DATABASE_URL:'postgresql://coroinhas_owner:fixture@fixture.neon.tech/coroinhas',PUSH_TEST_ALLOWED_SUBSCRIPTIONS:subscription,PUSH_TEST_NOTIFICATION_ID:notification,PUSH_TEST_DISPATCH_APPROVED:approved?'yes':'no',PUSH_TEST_VAPID_PUBLIC_KEY:'fixture',PUSH_TEST_VAPID_PRIVATE_KEY:'fixture',PUSH_TEST_VAPID_SUBJECT:'mailto:fixture@example.invalid'},exitCode:0};
 class Client{
  async connect(){}async end(){}
  async query(sql:string,args?:any[]){
   if(sql.includes('SELECT branch_id'))return {rows:[{branch_id:'br-rough-hill-bcj6lzt1'}]};
   if(sql.includes('SELECT o.notification_id')){reads++;return {rowCount:cancelled&&reads>1?0:1,rows:[{notification_id:notification,subscription_id:subscription,endpoint:'https://push.example.invalid',p256dh:'fixture',auth:'fixture',title:'Fixture',body:'Fixture'}]};}
   if(sql.includes('RETURNING attempts'))return {rowCount:claimed?1:0,rows:claimed?[{attempts:1}]:[]};
   if(sql.includes('UPDATE migration_private.push_delivery_attempts'))updates.push({sql,args});
   return {rows:[],rowCount:0};
  }
 }
 const webpush={setVapidDetails(){},async sendNotification(){sends++;if(status)throw {statusCode:status};}};
 const code=fs.readFileSync('migration/push-test-dispatch.mjs','utf8').replace(/^import .*;$/gm,'');
 await vm.runInNewContext(`(async()=>{${code}\n})()`,{pg:{Client},webpush,URL,process:proc,console:{log:(s:string)=>output.push(s),error:(s:string)=>output.push(s)}});
 return {sends,updates,output,proc};
}
test('push dry run never invokes delivery',async()=>assert.equal((await dispatch({send:false})).sends,0));
test('push refuses send without explicit opt-in',async()=>await assert.rejects(dispatch({approved:false}),/not explicitly authorized/));
test('push successful or already claimed delivery is not sent twice',async()=>{assert.equal((await dispatch()).sends,1);assert.equal((await dispatch({claimed:false})).sends,0)});
test('push cancellation or changed preferences after claim prevents sending',async()=>assert.equal((await dispatch({cancelled:true})).sends,0));
test('push treats expired subscriptions as terminal and server failures as retryable',async()=>{
 for(const [status,expected] of ([[410,'permanent_failure'],[503,'retry']] as const)){
  const r=await dispatch({status});assert.equal(r.sends,1);assert.ok(r.updates.some(x=>x.args?.[2]===expected));
 }
});
test('service worker tags distinguish notifications and deduplicate repeated event IDs',async()=>{
 const listeners:Record<string,Function>={};const tags:string[]=[];
 vm.runInNewContext(fs.readFileSync('public/push-sw.js','utf8'),{self:{addEventListener:(name:string,cb:Function)=>listeners[name]=cb,registration:{showNotification:async(_title:string,opts:any)=>tags.push(opts.tag)}}});
 for(const tag of [notification,notification,subscription])await listeners.push({data:{json:()=>({title:'Fixture',tag})},waitUntil:(p:Promise<unknown>)=>p});
 assert.deepEqual(tags,[notification,notification,subscription]);
});
