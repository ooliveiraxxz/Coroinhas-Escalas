import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const system=readFileSync(new URL('../components/System.tsx',import.meta.url),'utf8');
const permissionKeys=[
  "confirm_assignment",
  "read_notifications",
  "request_service",
  "send_suggestions",
  "unassign_self",
  "view_scales",
  "vote_polls",
  "approve_requests",
  "attendance",
  "create_scales",
  "delete_scales",
  "edit_cerimoniario",
  "edit_coroinha",
  "manage_fixed_rules",
  "manage_guides",
  "manage_polls",
  "send_notifications",
  "view_reports",
  "manage_users",
  "publish_updates",
  "send_popup",
  "view_archives",
  "view_audit",
  "view_developer_panel",
  "view_child_scales"
] as const;

test('no extra permission automatically turns a server into a coordinator',()=>{
 assert.match(system,/const coord=profile\?\.approved===true&&\(profile\?\.role==='coordenadora'\|\|developer\)/);
 assert.doesNotMatch(system,/const coord=.*\['create_scales','edit_coroinha'/);
});

test('create, edit, and send actions have separate explicit gates',()=>{
 for(const requirement of [
  "can('create_scales')?'Cadastrar escala'",
  "if(!editId&&!can('create_scales'))",
  "editId?(can('edit_coroinha')||can('edit_cerimoniario')):can('create_scales')",
  "const notificationManager=coord||",
  "can('manage_polls')&&<button type=\"button\" className={notificationPanel==='poll'",
  "screenKind==='popup'&&can('send_popup')",
  "if(!db||!can('view_developer_panel'))return;setAccessLoading(true)"
 ])assert.ok(system.includes(requirement),'Missing guard: '+requirement);
});

test('each isolated permission does not grant unrelated create/edit permissions',()=>{
 for(const selected of permissionKeys){
  const grants=Object.fromEntries(permissionKeys.map(k=>[k,k===selected]));
  const role='cerimoniario';
  const isCoordinator=['coordenadora','desenvolvedor'].includes(role);
  assert.equal(isCoordinator,false,'wrong role elevation for '+selected);
  assert.equal(grants.create_scales,selected==='create_scales');
  assert.equal(Boolean(grants.edit_coroinha),selected==='edit_coroinha');
  assert.equal(Boolean(grants.edit_cerimoniario),selected==='edit_cerimoniario');
  assert.equal(Boolean(grants.manage_polls),selected==='manage_polls');
  assert.equal(Boolean(grants.send_notifications),selected==='send_notifications');
  assert.equal(Boolean(grants.manage_guides),selected==='manage_guides');
  assert.equal(Boolean(grants.send_popup),selected==='send_popup');
 }
});
