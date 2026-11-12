import test from 'node:test';
import assert from 'node:assert/strict';
import {compileQuery} from '../lib/neon/query';
const q=(path:string,method='GET',params='',body:unknown={},prefer='')=>compileQuery(path.split('/'),method,new URLSearchParams(params),body,prefer);
test('injection in filter is a value, never SQL',()=>{const r=q('profiles','GET','id=eq.%27%3BDELETE+FROM+profiles%3B--');assert.equal(r.values[0],"';DELETE FROM profiles;--");assert.ok(!r.text.includes('DELETE'));});
test('unknown tables, columns, RPCs and predicates fail closed',()=>{
 for(const f of [()=>q('auth.users'),()=>q('profiles','GET','select=password'),()=>q('profiles','GET','or=(id.eq.1)'),()=>q('rpc/get_push_targets','POST','',{}),()=>q('rpc/__proto__','POST','',{})])assert.throws(f);
});
test('no unfiltered destructive operation',()=>{assert.throws(()=>q('profiles','DELETE'));assert.throws(()=>q('profiles','PATCH','',{name:'x'}));});
test('parameter numbers remain correct with PATCH filters',()=>{const r=q('profiles','PATCH','id=eq.abc&select=id',{name:'Lucas'},'return=representation');assert.deepEqual(r.values,['abc','Lucas']);assert.equal(r.text,'UPDATE public."profiles" SET "name"=$2 WHERE "id" = $1 RETURNING "id"');});
test('upsert uses explicit known columns and conflict keys',()=>{const r=q('screen_announcement_dismissals','POST','on_conflict=announcement_id,user_id',{announcement_id:'a',user_id:'u'},'resolution=merge-duplicates');assert.match(r.text,/ON CONFLICT \("announcement_id","user_id"\) DO NOTHING/);assert.throws(()=>q('guides','POST','on_conflict=bad',{function_name:'x'},'resolution=merge-duplicates'));});
test('RPC arguments are cast and parameterized',()=>{const r=q('rpc/respond_assignment','POST','',{p_id:'id',p_action:'confirmar',p_reason:''});assert.match(r.text,/\$1::uuid/);assert.deepEqual(r.values,['id','confirmar','']);assert.throws(()=>q('rpc/respond_assignment','POST','',{p_sql:'SELECT 1'}));});
test('JSONB arrays for permission and automation RPCs are serialized as JSON, not PostgreSQL arrays',()=>{
 const changes=[{key:'view_archives',allowed:true}];
 const a=q('rpc/developer_apply_permissions','POST','',{p_user:'user-id',p_changes:changes,p_until:null,p_confirmation:'DESENVOLVEDOR'});
 assert.match(a.text,/"p_changes" => \$2::jsonb/);
 assert.equal(a.values[1],JSON.stringify(changes));
 const automations=[{key:'push_queue',enabled:true}];
 const b=q('rpc/developer_apply_automations','POST','',{p_changes:automations,p_confirmation:'DESENVOLVEDOR'});
 assert.equal(b.values[0],JSON.stringify(automations));
 const poll=q('rpc/poll_create','POST','',{p_question:'Teste',p_options:[{label:'Sim'}]});
 assert.equal(poll.values[1],JSON.stringify([{label:'Sim'}]));
 const response=q('rpc/poll_vote','POST','',{p_poll:'poll-id',p_options:['option-id']});
 assert.deepEqual(response.values,['poll-id',['option-id']]);
});
test('order and pagination reject SQL or excessive result sizes',()=>{assert.throws(()=>q('masses','GET','limit=1001'));assert.throws(()=>q('masses','GET','order=starts_at.desc%3BDROP'));const r=q('masses','GET','order=starts_at.asc&limit=80');assert.match(r.text,/ORDER BY "starts_at" ASC LIMIT \$1/);assert.deepEqual(r.values,[80]);});
test('batch insert shape cannot silently omit supplied fields',()=>{assert.throws(()=>q('messages','POST','',[{body:'a'},{body:'b',user_id:'u'}]));});
test('JSON preferences remain structured bound values',()=>{const prefs={enabled:true};const r=q('profiles','PATCH','id=eq.id',{notification_preferences:prefs});assert.deepEqual(r.values,['id',prefs]);});

test("profile reads use the masked security-invoker view",()=>{assert.match(q("profiles").text,/profile_directory/)});

test('upsert must target an actual primary or unique constraint',()=>{
 const legal=q('push_subscriptions','POST','on_conflict=endpoint',{user_id:'u',endpoint:'e',p256dh:'p',auth:'a'},'resolution=merge-duplicates');
 assert.match(legal.text,/ON CONFLICT \("endpoint"\)/);
 assert.throws(()=>q('push_subscriptions','POST','on_conflict=user_id',{user_id:'u'},'resolution=merge-duplicates'));
 assert.throws(()=>q('screen_announcement_dismissals','POST','on_conflict=announcement_id,announcement_id',{announcement_id:'a'},'resolution=merge-duplicates'));
 assert.throws(()=>q('profiles','GET','on_conflict=id'));
});
test('queries reject duplicate parameters and unsupported column filtering',()=>{
 assert.throws(()=>q('masses','GET','limit=2&limit=500'));
 assert.throws(()=>q('masses','GET','columns=id'));
 assert.throws(()=>q('rpc/record_site_access','POST','limit=1',{}));
});
test('all app-facing table schemas are allowlisted',()=>{
 for(const table of ['profiles','masses','assignments','notifications','requests','guides','messages','fixed_rules','site_updates','push_subscriptions','screen_announcements','screen_announcement_dismissals','audit_log']){
  assert.match(q(table).text,/^SELECT \* FROM public\./);
 }
});
test('all app-facing RPCs compile only parameterized calls',()=>{
 for(const name of ['developer_manage_user','approve_service_request','delete_notification','developer_usage_summary','edit_notification','mark_coordinator_message_seen','mark_notification_seen','reassign_legacy_function','record_site_access','respond_assignment','send_notification']){
  assert.match(q('rpc/'+name,'POST').text,/^SELECT public\./);
 }
});
