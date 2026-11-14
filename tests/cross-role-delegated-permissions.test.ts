import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {compileQuery} from '../lib/neon/query';
const ui=readFileSync(new URL('../components/System.tsx',import.meta.url),'utf8');
const service=readFileSync(new URL('../migration/sql/087-cross-role-catalog-enforcement.sql',import.meta.url),'utf8');
const policies=readFileSync(new URL('../migration/sql/088-cross-role-privacy-and-rls.sql',import.meta.url),'utf8');
const operations=readFileSync(new URL('../migration/sql/089-independent-approval-and-attendance.sql',import.meta.url),'utf8');
const legacy=readFileSync(new URL('../migration/sql/090-hide-obsolete-message-toggles.sql',import.meta.url),'utf8');

test('only catalogued functions can enable service eligibility, including non-native profiles',()=>{
 assert.match(service,/INSERT INTO public\.permission_catalog\(key,category,label,default_roles,sensitive\)/);
 assert.match(service,/eligible_to_serve/);
 assert.match(service,/is_eligible_service_member\(p_user uuid,p_group text\)/);
 assert.match(service,/user_has_catalog_permission\(p_user uuid,p_key text\)/);
 assert.match(service,/p_key NOT IN \('choose_theme','request_service','eligible_to_serve'/);
 assert.match(service,/IF p_key IN \('request_service','eligible_to_serve'/);
});
test('request, approval, direct assignment and automatic succession validate delegated membership',()=>{
 assert.match(policies,/public\.is_eligible_service_member\(user_id,service_group\)/);
 assert.match(service,/public\.is_eligible_service_member\(NEW\.server_id,NEW\.service_group\)/);
 assert.match(service,/public\.is_eligible_service_member\(r\.user_id,r\.service_group\)/);
 assert.match(service,/public\.is_eligible_service_member\(v_server,v_group\)/);
 assert.match(service,/public\.is_eligible_service_member\(p\.id,s\.service_group\)/);
});
test('parent read protections require an actual link or explicitly delegated general visibility',()=>{
 assert.match(policies,/public\.parent_child_links l/);
 assert.match(policies,/l\.parent_id=p\.id AND l\.child_id=p_server/);
 assert.match(policies,/public\.can_read_assignment_for_user\(mass_id,server_id,service_group,status\)/);
 assert.match(policies,/permission_key='view_scales'/);
});
test('developer data access respects revoked granular permissions',()=>{
 assert.match(policies,/public\.has_site_permission\('read_notifications'\)/);
 assert.match(policies,/public\.can_read_mass_for_user\(id\)/);
 assert.match(policies,/public\.can_update_mass_as_actor\(id\)/);
 assert.match(policies,/public\.has_site_permission\('create_scales'\)/);
});
test('service request and direct candidate selection are available to delegated parents and developers',()=>{
 assert.match(ui,/serviceGroupChoice\|\|myGroup/);
 assert.match(ui,/canBeSelected\(p,roleGroup\(r\)\)/);
 assert.match(ui,/canBeSelected\(p,serviceGroup\(a\)\)/);
 assert.match(ui,/serviceGroups\.includes\(serviceGroup\(a\)\)/);
 assert.match(ui,/can\('request_service'\)\?\['Quero servir'\]:\[\]/);
 assert.doesNotMatch(ui,/!coord&&!parent&&a\.server_id===user\.id/);
 assert.doesNotMatch(ui,/!coord&&!parent&&can\('request_service'\)/);
});
test('strict RPC gateway allows only the two audited service RPCs with parameterized arguments',()=>{
 const a=compileQuery(['rpc','my_service_groups'],'POST',new URLSearchParams(),{});
 assert.match(a.text,/public\."my_service_groups"/);
 const b=compileQuery(['rpc','service_candidate_list'],'POST',new URLSearchParams(),{p_group:'cerimoniario'});
 assert.match(b.text,/public\."service_candidate_list"/);
 assert.deepEqual(b.values,['cerimoniario']);
 assert.throws(()=>compileQuery(['rpc','service_candidate_list'],'POST',new URLSearchParams(),{p_group:'cerimoniario',evil:true}));
});

test('attendance can update presence but cannot arbitrarily change another member',()=>{
 assert.match(operations,/CREATE POLICY assignment_attendance_update/);
 assert.match(operations,/public\.has_site_permission\('attendance'\)/);
 assert.match(operations,/guard_delegated_assignment_update/);
 assert.match(operations,/NEW\.server_id IS DISTINCT FROM OLD\.server_id/);
 assert.match(ui,/delegatedAttendance=can\('attendance'\)/);
 assert.match(ui,/canEditGroup\(serviceGroup\(a\)\)\|\|can\('attendance'\)/);
});
test('requests can be approved without editing all functions of another group',()=>{
 assert.match(operations,/CREATE POLICY requests_manage/);
 assert.match(operations,/public\.has_site_permission\('approve_requests'\)/);
 assert.doesNotMatch(operations,/IF NOT public\.can_manage_service_group\(r\.service_group\)/);
 assert.match(operations,/r\.user_id=NEW\.server_id/);
 assert.match(operations,/pg_trigger_depth\(\)>1/);
});
test('native roles remain unchanged and explicit cross-role group selection is allowed',()=>{
 assert.match(service,/ARRAY\[\]::text\[\],false/);
 assert.match(ui,/const canOfferServiceGroup=/);
 assert.match(ui,/disabled=\{!canOfferServiceGroup\('cerimoniario'\)\}/);
 assert.match(ui,/disabled=\{!canOfferServiceGroup\('coroinha'\)\}/);
});
test('obsolete Mensagens permissions do not appear in management',()=>{
 assert.match(legacy,/WHERE c\.key NOT IN \('view_messages','mark_messages_seen'\)/);
 assert.doesNotMatch(ui,/'Notificações','Mensagens','Suporte'/);
});
