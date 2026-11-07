import test from 'node:test';
import assert from 'node:assert/strict';
import {dispatchPushBatch,type PushClaim,type PushDatabase} from '../lib/neon/push-dispatch';

const claim:PushClaim={
 notification_id:'00000000-0000-4000-8000-000000000010',
 subscription_id:'00000000-0000-4000-8000-000000000011',
 endpoint:'https://example.invalid/push',p256dh:'key',auth:'auth',
 title:'Aviso',body:'Teste',attempt_number:1
};
function database({claims=[claim],allowed=true,ack=true}:
 {claims?:PushClaim[];allowed?:boolean;ack?:boolean}={}){
 const calls:{sql:string;args?:unknown[]}[]=[];
 const db:PushDatabase={
  async query(sql,args){
   calls.push({sql,args});
   if(sql.includes('push_claim'))return {rows:claims as unknown as Record<string,unknown>[]};
   if(sql.includes('push_eligible'))return {rows:[{allowed}]};
   if(sql.includes('push_finish'))return {rows:[{done:ack}]};
   throw new Error('Unexpected database query');
  }
 };
 return {db,calls};
}
test('dormant queue does not deliver any push',async()=>{
 const {db}=database({claims:[]});
 let sends=0;
 const result=await dispatchPushBatch(db,async()=>{sends++});
 assert.deepEqual(result,{processed:0,sent:0,failed:0,skipped:0});
 assert.equal(sends,0);
});
test('successful push delivery is acknowledged once',async()=>{
 const {db,calls}=database();let sends=0;
 const result=await dispatchPushBatch(db,async()=>{sends++});
 assert.equal(result.sent,1);assert.equal(sends,1);
 const ack=calls.filter(c=>c.sql.includes('push_finish'));
 assert.equal(ack.length,1);
 assert.deepEqual(ack[0].args?.slice(2),[1,true,0]);
});
test('withdrawn subscription and preferences cannot receive push',async()=>{
 const {db,calls}=database({allowed:false});let sends=0;
 const result=await dispatchPushBatch(db,async()=>{sends++});
 assert.equal(sends,0);assert.equal(result.skipped,1);
 assert.deepEqual(calls.find(c=>c.sql.includes('push_finish'))?.args?.slice(2),[1,false,410]);
});
test('web push failure is retained for retry with sanitized HTTP status',async()=>{
 const {db,calls}=database();
 const result=await dispatchPushBatch(db,async()=>{throw {statusCode:503}});
 assert.equal(result.failed,1);
 assert.deepEqual(calls.find(c=>c.sql.includes('push_finish'))?.args?.slice(2),[1,false,503]);
});
test('successful delivery with failed acknowledgement does not mark push as failed',async()=>{
 const {db,calls}=database({ack:false});
 await assert.rejects(dispatchPushBatch(db,async()=>{}),/Delivery lease changed/);
 assert.equal(calls.filter(c=>c.sql.includes('push_finish')).length,1);
 assert.deepEqual(calls.find(c=>c.sql.includes('push_finish'))?.args?.slice(2),[1,true,0]);
});
test('rejects abnormal batch sizes before accessing database',async()=>{
 const {db,calls}=database();
 for(const limit of [-1,0,1.5,21,Number.NaN]){
  await assert.rejects(dispatchPushBatch(db,async()=>{},limit));
 }
 assert.equal(calls.length,0);
});
