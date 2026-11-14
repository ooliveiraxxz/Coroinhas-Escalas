import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const system=readFileSync(new URL('../components/System.tsx',import.meta.url),'utf8');
const center=readFileSync(new URL('../components/PermissionCenter.tsx',import.meta.url),'utf8');
const migration=readFileSync(new URL('../migration/sql/084-opt-in-theme-permission.sql',import.meta.url),'utf8');

test('theme picker is visible to every authorized role, never by role alone',()=>{
 assert.match(system,/\{canChooseTheme&&<div className="developer-theme-preference"/);
 assert.match(system,/const canChooseTheme=runtimePermissions\.choose_theme===true/);
 assert.match(system,/id="developer-theme-select"/);
 assert.match(system,/<option value="coroinha">Coroinha — vinho<\/option>/);
 assert.match(system,/<option value="cerimoniario">Cerimoniário — preto e cinza<\/option>/);
});
test('native role theme remains when permission is off or preference not chosen',()=>{
 assert.match(system,/const nativeCeremonyTheme=ceremony\|\|/);
 assert.match(system,/const ceremonyTheme=canChooseTheme&&/);
 assert.match(system,/\?profile\?\.theme_preference==='cerimoniario':nativeCeremonyTheme/);
 assert.match(system,/className=\{'app'\+\(ceremonyTheme\?' ceremony-theme':''\)\}/);
 assert.match(system,/screenPopup&&<div className=\{"screen-popup-overlay"\+\(ceremonyTheme\?" screen-popup-ceremony":""\)\}/);
});
test('personal preference only changes theme and cannot bypass permission',()=>{
 assert.match(system,/db\.rpc\('set_my_theme',\{p_theme:next\}\)/);
 assert.match(system,/if\(!db\|\|!user\?\.id\|\|!canChooseTheme/);
 assert.match(system,/setProfile\(previous=>previous\?\{\.\.\.previous,theme_preference:next\}:previous\)/);
 assert.match(migration,/IF v_id IS NULL OR NOT public\.has_site_permission\('choose_theme'\) THEN/);
 assert.match(migration,/UPDATE public\.profiles SET theme_preference=p_theme WHERE id=v_id AND approved/);
 assert.match(migration,/REVOKE ALL ON FUNCTION public\.developer_set_my_theme\(text\) FROM PUBLIC,coroinhas_app,coroinhas_gateway/);
});
test('permission exists but is disabled for all by default, developer may only delegate theme to developers',()=>{
 assert.match(migration,/VALUES\('choose_theme','Desenvolvedor','Escolher tema visual do aplicativo',ARRAY\[\]::text\[\],false\)/);
 assert.match(migration,/IF p_key='choose_theme' THEN/);
 assert.match(migration,/IF p.role='desenvolvedor' THEN RETURN true; END IF/);
 assert.ok(migration.indexOf("IF p_key='choose_theme'")<migration.indexOf("IF p.role='desenvolvedor'"));
 assert.match(migration,/c\.key<>'choose_theme'/);
 assert.match(migration,/AND x->>'key'<>'choose_theme' THEN/);
 assert.match(center,/const eligible=users\.sort/);
 assert.match(center,/current\?\.role!=='desenvolvedor'\|\|r\.key==='choose_theme'/);
});
