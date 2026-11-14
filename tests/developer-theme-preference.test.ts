import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const system=readFileSync(new URL('../components/System.tsx',import.meta.url),'utf8');
const sql=readFileSync(new URL('../migration/sql/083-developer-theme-preference.sql',import.meta.url),'utf8');

test('developer-only theme picker appears inside Meu perfil',()=>{
 assert.match(system, /\{developer&&<div className="developer-theme-preference"/);
 assert.match(system, /id="developer-theme-select"/);
 assert.match(system, /<option value="coroinha">Coroinha — vinho<\/option>/);
 assert.match(system, /<option value="cerimoniario">Cerimoniário — preto e cinza<\/option>/);
});
test('ceremonial appearance follows saved developer preference, not permission grants',()=>{
 assert.match(system,/const ceremonyTheme=ceremony\|\|\(developer&&profile\?\.theme_preference==='cerimoniario'\)/);
 assert.match(system,/className=\{'app'\+\(ceremonyTheme\?' ceremony-theme':''\)\}/);
 assert.match(system,/screenPopup&&<div className=\{"screen-popup-overlay"\+\(ceremonyTheme\?" screen-popup-ceremony":""\)\}/);
});
test('the saved preference does not modify role or coordination group',()=>{
 assert.match(system,/db\.rpc\('developer_set_my_theme',\{p_theme:next\}\)/);
 assert.match(system,/setProfile\(previous=>previous\?\{\.\.\.previous,theme_preference:next\}:previous\)/);
 assert.doesNotMatch(sql,/UPDATE public\.profiles SET (?:role|coordination_group)/);
});
test('database function restricts writes to the authenticated developer and validates value',()=>{
 assert.match(sql,/v_id:=auth\.uid\(\)/);
 assert.match(sql,/WHERE id=v_id AND approved=true AND role='desenvolvedor'/);
 assert.match(sql,/p_theme NOT IN \('coroinha','cerimoniario'\)/);
 assert.match(sql,/UPDATE public\.profiles SET theme_preference=p_theme WHERE id=v_id/);
 assert.match(sql,/REVOKE ALL ON FUNCTION public\.developer_set_my_theme\(text\) FROM PUBLIC/);
 assert.match(sql,/GRANT EXECUTE ON FUNCTION public\.developer_set_my_theme\(text\) TO coroinhas_app/);
});
