import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const ui=readFileSync(new URL('../components/System.tsx',import.meta.url),'utf8');

test('Coordinator quick bar shows Notificações instead of Relatórios',()=>{
 assert.match(ui,/developer\?\[ChartColumn,'Relatórios'\]:\[Bell,'Notificações'\]/);
 assert.match(ui,/coord\?\['Início','Missas',developer\?'Usuários':groupUserPlural,developer\?'Relatórios':'Notificações'\]/);
 assert.match(ui,/coord\?\['Início','Missas',groupUserPlural,'Relatórios','Escala automática'/);
});
test('Reports remains in coordinator menu only when view_reports is enabled',()=>{
 assert.match(ui,/label!=='Relatórios'\|\|\(!developer&&can\('view_reports'\)\)/);
 assert.match(ui,/label!=='Notificações'\|\|can\('read_notifications'\)/);
});
test('Developer quick Relatórios opens the full developer panel and reloads data',()=>{
 assert.match(ui,/developer&&l==='Relatórios'\?'Painel desenvolvedor':l/);
 assert.match(ui,/target==='Painel desenvolvedor'\)\{void showDeveloper\(\);void loadRecentAccess\(\)\}/);
 assert.match(ui,/view==='Painel desenvolvedor'&&can\('view_developer_panel'\)/);
 assert.match(ui,/\{developer\?'Relatórios':'Painel do desenvolvedor'\}/);
});
test('Developer hides the quick reports shortcut if its dedicated permission is disabled',()=>{
 assert.match(ui,/l!=='Relatórios'\|\|\(developer\?can\('view_developer_panel'\):can\('view_reports'\)\)/);
});
test('Developer panel no longer appears in the developer menu',()=>{
 const start=ui.indexOf('const menuItems=');
 const end=ui.indexOf(':coord?',start);
 assert.ok(start>=0&&end>start);
 assert.doesNotMatch(ui.slice(start,end),/Painel desenvolvedor/);
});
