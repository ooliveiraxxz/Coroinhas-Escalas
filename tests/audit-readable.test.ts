import test from 'node:test';
import assert from 'node:assert/strict';
import {groupAuditEntries,formatAuditEntry,type AuditEntry} from '../lib/audit/format';

const base:AuditEntry={id:1,happened_at:'2026-11-12T04:13:40.000Z',actor_id:'123',actor_name:'Lucas Santana',actor_email:'teste@exemplo.com',table_name:'notifications',action:'INSERT',after_data:{title:'HAHAHA',body:'hacker',user_id:'recipient-1',event_key:'general'}};
test('same campaign for multiple recipients becomes one readable audit event',()=>{
 const rows=[base,{...base,id:2,after_data:{...base.after_data,user_id:'recipient-2'}},{...base,id:3,after_data:{...base.after_data,user_id:'recipient-3'}}];
 const result=groupAuditEntries(rows);
 assert.equal(result.length,1);
 assert.equal(result[0].recipient_count,3);
 const info=formatAuditEntry(result[0]);
 assert.match(info.detail,/3 destinatários/);
 assert.match(info.title,/CRIADO — NOTIFICAÇÃO/);
 assert.match(info.when,/12\/11\/2026/);
});
test('distinct notification messages and events are never collapsed',()=>{
 const data=[base,{...base,id:4,after_data:{...base.after_data,title:'Outro aviso'}},{...base,id:5,happened_at:'2026-11-12T04:13:41.000Z'}];
 assert.equal(groupAuditEntries(data).length,3);
});
test('each scale event remains independent, with clear actor and mass name',()=>{
 const mass:AuditEntry={id:10,happened_at:'2026-11-12T04:53:22Z',actor_name:'Lucas Santana',actor_email:'teste@exemplo.com',actor_id:'user-1',table_name:'masses',action:'INSERT',after_data:{title:'Missa do Santíssimo',starts_at:'2026-11-13T19:00:00Z'}};
 const result=formatAuditEntry(mass);
 assert.equal(result.title,'CRIADO — ESCALA');
 assert.match(result.detail,/Lucas Santana criou a escala “Missa do Santíssimo”/);
 assert.equal(groupAuditEntries([mass,{...mass,id:11}]).length,2);
});
test('internal automation codes are converted to Portuguese names',()=>{
 const auto:AuditEntry={id:20,happened_at:'2026-11-12T04:13:40Z',table_name:'service_settings',action:'INSERT',after_data:{key:'auto_approval_3h',enabled:true}};
 const info=formatAuditEntry(auto);
 assert.match(info.detail,/Aprovação automática de solicitações após 3 horas/);
 assert.doesNotMatch(info.detail,/auto_approval_3h/);
});
test('reading a notification is described explicitly',()=>{
 const info=formatAuditEntry({...base,action:'UPDATE',before_data:{title:'Lembrete',seen:false},after_data:{title:'Lembrete',seen:true}});
 assert.match(info.detail,/marcou a notificação “Lembrete” como lida/);
});

test('one permission grant operation is displayed as one audit item',()=>{
 const at='2026-11-12T04:12:22.000Z';
 const a:AuditEntry={id:1,happened_at:at,actor_id:'dev',actor_name:'DESENVOLVEDOR',table_name:'permission_rules',action:'INSERT',after_data:{permission_key:'view_archives',subject_user:'u',batch_id:'batch-1',allowed:true,expires_at:'2026-11-13T04:00:00.000Z'}};
 const result=groupAuditEntries([a,{...a,id:2,after_data:{...a.after_data,permission_key:'view_reports'}},{...a,id:3,after_data:{...a.after_data,permission_key:'manage_users'}}]);
 assert.equal(result.length,1);
 assert.equal(result[0].permission_count,3);
 const readable=formatAuditEntry(result[0]);
 assert.match(readable.title,/3 PERMISSÕES/);
 assert.match(readable.detail,/Visualizar Arquivados/);
 assert.match(readable.detail,/Gerenciar usuários/);
});
test('bulk revocation is a single event but separate operations remain separate',()=>{
 const before={permission_key:'view_archives',subject_user:'u',expires_at:'2026-11-13T04:00:00.000Z'};
 const a:AuditEntry={id:10,happened_at:'2026-11-12T05:00:00.000Z',actor_id:'dev',actor_name:'DEV',table_name:'permission_rules',action:'UPDATE',before_data:before,after_data:{...before,expires_at:'2026-11-12T05:00:00.000Z',batch_id:'rev-batch'}};
 const grouped=groupAuditEntries([a,{...a,id:11,before_data:{...before,permission_key:'send_notifications'},after_data:{...a.after_data,permission_key:'send_notifications'}}]);
 assert.equal(grouped.length,1);
 assert.match(formatAuditEntry(grouped[0]).title,/REVOGADAS — 2 PERMISSÕES/);
 assert.equal(groupAuditEntries([a,{...a,id:11,after_data:{...a.after_data,batch_id:'another-batch'}}]).length,2);
});
