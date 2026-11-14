import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const system=readFileSync(new URL('../components/System.tsx',import.meta.url),'utf8');
const health=readFileSync(new URL('../components/DeveloperHealth.tsx',import.meta.url),'utf8');
const css=readFileSync(new URL('../app/globals.css',import.meta.url),'utf8');
const sql=readFileSync(new URL('../migration/sql/082-ceremonial-usage-metric.sql',import.meta.url),'utf8');

test('utilization indicators include a separate approved Cerimoniários count',()=>{
 assert.match(system,/\['Cerimoniários',usage\.ceremoniaries\]/);
 assert.match(sql,/'ceremoniaries',\(SELECT count\(\*\) FROM public\.profiles WHERE role='cerimoniario' AND approved\)/);
 assert.match(sql,/has_site_permission\('view_developer_panel'\)/);
});
test('delegated content controls inherit Cerimoniário colors instead of hardcoded burgundy',()=>{
 assert.doesNotMatch(system,/color:'#fff',background:'linear-gradient\(130deg,#801b34,#a83450\)'/);
 assert.match(css,/\.app\.ceremony-theme \.developer-content-grid button\.btn\{/);
 assert.match(css,/\.app\.ceremony-theme \.developer-metrics \.metric strong/);
});
test('health charts take their colors from CSS theme',()=>{
 assert.match(health,/className="health-progress-track"/);
 assert.match(health,/className="health-history-bar"/);
 assert.match(css,/\.app\.ceremony-theme \.health-progress-fill\.normal/);
 assert.doesNotMatch(health,/background:'#87263d'/);
});
