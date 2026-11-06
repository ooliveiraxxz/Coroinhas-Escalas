import test from 'node:test';
import assert from 'node:assert/strict';
import {compileQuery} from '../lib/neon/query';
const q=(path:string,method='GET',params='',body:unknown={},prefer='')=>compileQuery(path.split('/'),method,new URLSearchParams(params),body,prefer);
test('injection in filter is a value, never SQL',()=>{const r=q('profiles','GET','id=eq.%27%3BDELETE+FROM+profiles%3B--');assert.equal(r.values[0],"';DELETE FROM profiles;--");assert.ok(!r.text.includes('DELETE'));});
test('unknown tables, columns, RPCs and predicates fail closed',()=>{
 for(const f of [()=>q('auth.users'),()=>q('profiles','GET','select=password'),()=>q('profiles','GET','or=(id.eq.1)'),()=>q('rpc/get_push_targets','POST','',{}),()=>q('rpc/developer_manage_user','POST','',{}),()=>q('rpc/__proto__','POST','',{})])assert.throws(f);
});
test('no unfiltered destructive operation',()=>{assert.throws(()=>q('profiles','DELETE'));assert.throws(()=>q('profiles','PATCH','',{name:'x'}));});
test('parameter numbers remain correct with PATCH filters',()=>{const r=q('profiles','PATCH','id=eq.abc&select=id',{name:'Lucas'},'return=representation');assert.deepEqual(r.values,['abc','Lucas']);assert.equal(r.text,'UPDATE public."profiles" SET "name"=$2 WHERE "id" = $1 RETURNING "id"');});
test('upsert uses explicit known columns and conflict keys',()=>{const r=q('screen_announcement_dismissals','POST','on_conflict=announcement_id,user_id',{announcement_id:'a',user_id:'u'},'resolution=merge-duplicates');assert.match(r.text,/ON CONFLICT \("announcement_id","user_id"\) DO NOTHING/);assert.throws(()=>q('guides','POST','on_conflict=bad',{function_name:'x'},'resolution=merge-duplicates'));});
test('RPC arguments are cast and parameterized',()=>{const r=q('rpc/respond_assignment','POST','',{p_id:'id',p_action:'confirmar',p_reason:''});assert.match(r.text,/\$1::uuid/);assert.deepEqual(r.values,['id','confirmar','']);assert.throws(()=>q('rpc/respond_assignment','POST','',{p_sql:'SELECT 1'}));});
test('order and pagination reject SQL or excessive result sizes',()=>{assert.throws(()=>q('masses','GET','limit=1001'));assert.throws(()=>q('masses','GET','order=starts_at.desc%3BDROP'));const r=q('masses','GET','order=starts_at.asc&limit=80');assert.match(r.text,/ORDER BY "starts_at" ASC LIMIT \$1/);assert.deepEqual(r.values,[80]);});
test('batch insert shape cannot silently omit supplied fields',()=>{assert.throws(()=>q('messages','POST','',[{body:'a'},{body:'b',user_id:'u'}]));});
test('JSON preferences remain structured bound values',()=>{const prefs={enabled:true};const r=q('profiles','PATCH','id=eq.id',{notification_preferences:prefs});assert.deepEqual(r.values,['id',prefs]);});
