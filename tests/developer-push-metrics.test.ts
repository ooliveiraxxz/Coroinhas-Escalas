import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const sql=readFileSync(new URL('../migration/sql/092-developer-push-metrics.sql',import.meta.url),'utf8');
const component=readFileSync(new URL('../components/System.tsx',import.meta.url),'utf8');

test('Developer metrics do not change accounts or subscriptions',()=>{
 assert.match(sql,/public\.has_site_permission\('view_developer_panel'\)/);
 assert.match(sql,/count\(DISTINCT endpoint\).*public\.push_subscriptions/);
 assert.match(sql,/count\(DISTINCT user_id\).*public\.push_subscriptions/);
 assert.match(sql,/p\.approved AND NOT EXISTS/);
 assert.doesNotMatch(sql,/\b(DELETE|TRUNCATE|DROP|INSERT|UPDATE)\s+(FROM\s+|INTO\s+|TABLE\s+)?(public\.)?(profiles|push_subscriptions|neon_auth)/i);
});
test('Developer dashboard shows push metrics without inventing PWA install counts',()=>{
 for(const field of ['push_devices','push_users','approved_without_push']) assert.ok(component.includes('usage.'+field));
 assert.match(component,/Aparelhos com notificações ativadas/);
 assert.doesNotMatch(component,/\['PWAs instalados'/);
});
