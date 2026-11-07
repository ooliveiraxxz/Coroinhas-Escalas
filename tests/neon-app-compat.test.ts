import test from 'node:test';
import assert from 'node:assert/strict';
import {compileQuery} from '../lib/neon/query';

const q=(path:string,method='GET',params='',body:unknown={},prefer='')=>
  compileQuery(path.split('/'),method,new URLSearchParams(params),body,prefer);

test('staging reads keep projection, filters, sorting and limits parameterized',()=>{
 const r=q('notifications','GET','select=id,title,seen&user_id=eq.00000000-0000-4000-8000-000000000001&order=created_at.desc&limit=80');
 assert.equal(r.text,'SELECT "id","title","seen" FROM public."notifications" WHERE "user_id" = $1 ORDER BY "created_at" DESC LIMIT $2');
 assert.deepEqual(r.values,['00000000-0000-4000-8000-000000000001',80]);
});
test('profile lookup uses privacy view while updates retain RLS table',()=>{
 const get=q('profiles','GET','id=eq.x');
 const update=q('profiles','PATCH','id=eq.x',{notification_preferences:{enabled:false}},'return=representation');
 assert.match(get.text,/FROM public\."profile_directory"/);
 assert.match(update.text,/UPDATE public\."profiles"/);
 assert.deepEqual(update.values,['x',{enabled:false}]);
});
test('migration mass creation preserves singular PostgREST id projection',()=>{
 const r=q('masses','POST','select=id',{title:'Missa',starts_at:'2026-11-10T19:00:00-03:00',created_by:'u'},'return=representation');
 assert.match(r.text,/INSERT INTO public\."masses"/);
 assert.match(r.text,/RETURNING "id"$/);
 assert.deepEqual(r.values,['Missa','2026-11-10T19:00:00-03:00','u']);
});
test('assignment presence update and protected deletion require id filters',()=>{
 const r=q('assignments','PATCH','id=eq.a&select=*',{status:'presente'},'return=representation');
 assert.match(r.text,/UPDATE public\."assignments" SET "status"=\$2 WHERE "id" = \$1 RETURNING \*/);
 assert.throws(()=>q('assignments','DELETE'));
 assert.match(q('assignments','DELETE','id=eq.a&select=id',{},'return=representation').text,/RETURNING "id"$/);
});
test('safe push subscription upsert on endpoint supports unique constraint',()=>{
 const r=q('push_subscriptions','POST','on_conflict=endpoint',{user_id:'user',endpoint:'https://endpoint.example',auth:'secret',p256dh:'key'},'resolution=merge-duplicates');
 assert.match(r.text,/ON CONFLICT \("endpoint"\) DO UPDATE SET/);
 assert.ok(r.values.includes('https://endpoint.example'));
});
test('coordinator message reads allow null exclusions',()=>{
 const r=q('notifications','GET','group_id=not.is.null&order=created_at.desc&limit=400');
 assert.match(r.text,/WHERE "group_id" IS NOT NULL ORDER BY "created_at" DESC LIMIT \$1$/);
});
test('developer RPC allows optional default parameters but no injected names',()=>{
 const r=q('rpc/developer_manage_user','POST','',{p_user:'id',p_action:'ban'});
 assert.match(r.text,/"p_action" => \$2::text/);
 assert.throws(()=>q('rpc/developer_manage_user','POST','',{p_user:'id',p_action:'ban',unexpected:'x'}));
});
test('all listed app RPC names are supported through allowlisted compiler',()=>{
 const names=['approve_service_request','delete_notification','developer_manage_user','developer_usage_summary','edit_notification','mark_coordinator_message_seen','mark_notification_seen','reassign_legacy_function','record_site_access','respond_assignment','send_notification'];
 for(const name of names)assert.doesNotThrow(()=>q('rpc/'+name,'POST','',{}));
});
test('forbid unsupported operators, cross-table projections and unsafe SQL syntax',()=>{
 for(const params of ['select=id,password','id=like.%25','id=in.(1,2)','or=(id.eq.1)','order=id.desc.nullsfirst','limit=100000','select=secret(*)'])
  assert.throws(()=>q('profiles','GET',params),params);
});
