import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const sql=readFileSync(new URL('../migration/sql/091-delegated-role-change-guard.sql',import.meta.url),'utf8');
const ui=readFileSync(new URL('../components/System.tsx',import.meta.url),'utf8');

test('authorized role changes go through scoped administrative RPC',()=>{
 assert.match(sql,/set_config\('app\.delegated_role_change_target',p_user::text,true\)/);
 assert.match(sql,/public\.has_site_permission\('manage_users'\)/);
 assert.match(sql,/current_setting\('app\.delegated_role_change_target',true\)=OLD\.id::text/);
 assert.match(sql,/IF NOT public\.is_developer\(\) AND \(v_role='desenvolvedor' OR p_role='desenvolvedor'\)/);
});
test('direct profile role edits without an authorized RPC remain blocked',()=>{
 assert.match(sql,/AND NOT public\.is_developer\(\)/);
 assert.match(sql,/RAISE EXCEPTION 'Somente desenvolvedor altera papéis e grupos'/);
 assert.match(ui,/db!\.rpc\('developer_manage_user',\{p_user:p\.id,p_action:'role',p_role:role\}\)/);
});
