import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {compileQuery} from '../lib/neon/query';

const system=readFileSync(new URL('../components/System.tsx',import.meta.url),'utf8');
const center=readFileSync(new URL('../components/PermissionCenter.tsx',import.meta.url),'utf8');
const schema=readFileSync(new URL('../migration/sql/085-profile-theme-directory.sql',import.meta.url),'utf8');
const grants=readFileSync(new URL('../migration/sql/086-developer-self-permission-toggles.sql',import.meta.url),'utf8');

test('Neon RPC gateway accepts self theme change with a parameterized query',()=>{
 const query=compileQuery(['rpc','set_my_theme'],'POST',new URLSearchParams(),{p_theme:'cerimoniario'});
 assert.match(query.text,/public\."set_my_theme"\("p_theme" => \$1::text\)/);
 assert.deepEqual(query.values,['cerimoniario']);
 assert.throws(()=>compileQuery(['rpc','set_my_theme'],'POST',new URLSearchParams(),{p_theme:'cerimoniario',role:'desenvolvedor'}));
});
test('profile directory returns the theme only to the signed-in owner',()=>{
 assert.match(schema,/CASE WHEN id = auth\.uid\(\) THEN theme_preference ELSE NULL::text END AS theme_preference/);
 const query=compileQuery(['profiles'],'GET',new URLSearchParams({select:'id,theme_preference'}),{});
 assert.match(query.text,/profile_directory/);
 assert.match(query.text,/theme_preference/);
});
test('developer can manage own catalog permissions while retaining role-based recovery',()=>{
 assert.match(center,/current\.id===viewerId\|\|r\.key==='choose_theme'/);
 assert.match(system,/Object\.hasOwn\(runtimePermissions,key\)\?runtimePermissions\[key\]===true:developer/);
 assert.match(system,/view==='Permissões'&&developer/);
 assert.match(grants,/subject_user=p\.id AND permission_key=p_key/);
 assert.match(grants,/IF FOUND THEN RETURN v_allowed; END IF;[\s\S]*?RETURN EXISTS/);
 assert.match(grants,/p_user<>auth\.uid\(\) AND x->>'key'<>'choose_theme'/);
 assert.match(grants,/clock_timestamp\(\)/);
});
