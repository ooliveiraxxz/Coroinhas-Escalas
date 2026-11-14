import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const css=readFileSync(new URL('../app/globals.css',import.meta.url),'utf8');
const sys=readFileSync(new URL('../components/System.tsx',import.meta.url),'utf8');

test('Cerimoniário appearance is tied to role, not granted permissions',()=>{
 assert.match(sys,/const ceremony=profile\?\.approved===true&&profile\?\.role==='cerimoniario'/);
 assert.match(sys,/ceremony\|\|myGroup==='cerimoniario'&&coord&&!developer/);
 assert.match(sys,/ceremony-theme/);
});

test('role accent tokens keep the original coroinha theme unchanged',()=>{
 assert.match(css,/:root\{--wine:#[0-9a-f]{6}/);
 assert.match(css,/\.app\.ceremony-theme\{[\s\S]*?--role-accent:#292929/);
 assert.match(css,/--role-accent-strong:#1d1d1d/);
 assert.match(css,/--role-accent-soft:#f0f0f0/);
});

test('delegated developer panels, audit, users and messaging use ceremony scope',()=>{
 const local=['.developer-content-grid button','.developer-access-item strong','.users-person-meta','.audit-readable-title','.notification-subheading','.poll-heading strong','.poll-create h3','.notification-central-tabs button','.notification-section-tabs button'];
 for(const selector of local)assert.ok(css.includes(selector),'Missing color guard: '+selector);
 assert.match(css,/\.app\.ceremony-theme :is\([\s\S]*?\.developer-content-grid button/);
 assert.match(css,/\.app\.ceremony-theme :is\([\s\S]*?\.notification-central-tabs button\.active/);
});

test('chat and portal popup respect ceremonial role outside app root',()=>{
 assert.match(css,/body:has\(\.app\.ceremony-theme\) :is\([\s\S]*?\.support-chat-compose \.support-chat-send/);
 assert.match(css,/\.screen-popup-overlay\.screen-popup-ceremony :is\(/);
 assert.match(css,/\.screen-popup-overlay\.screen-popup-ceremony \.screen-popup-image/);
});

test('interactive controls inherit grayscale accessible active state',()=>{
 assert.match(css,/\.app\.ceremony-theme :is\([\s\S]*?\.poll-check input/);
 assert.match(css,/accent-color:var\(--role-accent\)/);
 assert.match(css,/color:var\(--role-accent-contrast\)/);
});
