import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const legacy=readFileSync(new URL('../migration/sql/045-complete-permissions-center.sql',import.meta.url),'utf8');
const archive=readFileSync(new URL('../migration/sql/052-archives-retention-and-permissions.sql',import.meta.url),'utf8');
const additions=readFileSync(new URL('../migration/qa-message-permissions-20261113.sql',import.meta.url),'utf8');
const system=readFileSync(new URL('../components/System.tsx',import.meta.url),'utf8');
const defaultRoles=['coroinha','cerimoniario','pai','coordenadora','desenvolvedor'] as const;

test('all five roles remain selectable in the accounts screen',()=>{
 for(const role of defaultRoles)assert.ok(system.includes('<option value="'+role+'">'),'missing role '+role);
});
test('all newly delegated permissions have matching UI and database protection',()=>{
 for(const key of ['view_messages','mark_messages_seen']){
  assert.match(additions,new RegExp("'"+key+"'"));
  assert.ok(system.includes("can('"+key+"')"),'missing UI gate '+key);
  assert.ok(additions.includes("has_site_permission('"+key+"')"),'missing DB guard '+key);
 }
});
test('existing coordinator notification and scale permission definitions remain available',()=>{
 for(const key of ['create_scales','edit_coroinha','edit_cerimoniario','send_notifications','manage_polls','view_child_scales']){
  assert.ok(legacy.includes("'"+key+"'"),'baseline missing permission '+key);
 }
 assert.ok(archive.includes('view_archives'),'archived view missing');
});
