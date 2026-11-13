import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const system=readFileSync(new URL('../components/System.tsx',import.meta.url),'utf8');
const migration=readFileSync(new URL('../migration/qa-message-permissions-20261113.sql',import.meta.url),'utf8');
const center=readFileSync(new URL('../components/PermissionCenter.tsx',import.meta.url),'utf8');

test('the management UI renders every catalog item supplied by the server',()=>{
 assert.match(center,/permRows\.filter\(r=>r\.category===group\)\.map\(row=>/);
 assert.match(center,/developer_permission_snapshot/);
});
test('messages inbox and seen-state operations each have a separate UI permission',()=>{
 assert.match(system,/view==='Mensagens'&&can\('view_messages'\)/);
 assert.match(system,/!m\.seen&&can\('mark_messages_seen'\)/);
 assert.match(system,/label!=='Mensagens'\|\|can\('view_messages'\)/);
});
test('messages catalog has two independent keys with safe coordinator defaults',()=>{
 for(const key of ['view_messages','mark_messages_seen']){
  assert.ok(migration.includes("'"+key+"'"));
 }
 assert.match(migration,/ALTER POLICY messages_read/);
 assert.match(migration,/user_id=auth\.uid\(\) OR public\.has_site_permission\('view_messages'\)/);
});
test('mark-seen requires reading and marking permissions on the server',()=>{
 assert.match(migration,/NOT public\.has_site_permission\('mark_messages_seen'\)/);
 assert.match(migration,/NOT public\.has_site_permission\('view_messages'\)/);
 assert.match(migration,/archived_at IS NULL/);
});
