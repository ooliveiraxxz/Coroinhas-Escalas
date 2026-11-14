import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const gh=readFileSync(new URL('../app/api/developer/github-problems/route.ts',import.meta.url),'utf8');
const vercel=readFileSync(new URL('../app/api/developer/vercel-problems/route.ts',import.meta.url),'utf8');
const health=readFileSync(new URL('../migration/sql/081-delegated-developer-health.sql',import.meta.url),'utf8');
const system=readFileSync(new URL('../components/System.tsx',import.meta.url),'utf8');

test('GitHub and Vercel health endpoints check delegated panel permission server-side',()=>{
 for(const [name,source] of [['GitHub',gh],['Vercel',vercel]]){
  assert.match(source,/SELECT public\.has_site_permission\('view_developer_panel'\) AS allowed/,name);
  assert.doesNotMatch(source,/SELECT public\.is_developer\(\) AS allowed/,name);
  assert.match(source,/if\(!role\.rows\[0\]\?\.allowed\)return reply\(/,name);
 }
});
test('Neon health RPC honors same delegated permission and blocks missing permission',()=>{
 assert.match(health,/IF NOT public\.has_site_permission\('view_developer_panel'\) THEN RAISE EXCEPTION/);
 assert.doesNotMatch(health,/IF NOT public\.is_developer\(\)/);
});
test('UI still protects the developer panel behind explicit permission',()=>{
 assert.match(system,/view==='Painel desenvolvedor'&&can\('view_developer_panel'\)/);
});
