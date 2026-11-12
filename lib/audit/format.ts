export type AuditEntry = {
 id:number|string;happened_at:string;actor_id?:string|null;actor_email?:string|null;actor_name?:string|null;
 table_name:string;action:'INSERT'|'UPDATE'|'DELETE';record_id?:string|null;
 before_data?:Record<string,unknown>|null;after_data?:Record<string,unknown>|null;
 related_mass_name?:string|null;recipient_count?:number;
 permission_details?:{key:string;allowed:boolean;revoked:boolean}[];permission_count?:number;related_user_name?:string|null;
 activity_details?:{id:string;title:string;at:string}[];activity_count?:number;activity_started_at?:string;activity_ended_at?:string;activity_kind?:'archived'|'read';
};
const kinds:Record<string,string>={
 masses:'ESCALA',assignments:'FUNÇÃO DA ESCALA',requests:'SOLICITAÇÃO PARA SERVIR',
 notifications:'NOTIFICAÇÃO',profiles:'CADASTRO',permission_rules:'PERMISSÃO',
 guides:'ORIENTAÇÃO',fixed_rules:'ESCALA AUTOMÁTICA',polls:'ENQUETE',
 poll_votes:'VOTO NA ENQUETE',open_questions:'PERGUNTA',open_question_answers:'RESPOSTA À PERGUNTA',
 messages:'MENSAGEM',site_updates:'ATUALIZAÇÃO DO SITE',
 screen_announcements:'AVISO NA TELA',push_subscriptions:'NOTIFICAÇÕES DO APARELHO',
 service_settings:'AUTOMAÇÃO',banned_emails:'BLOQUEIO DE CONTA',support_tickets:'ATENDIMENTO DE SUPORTE',
 support_messages:'MENSAGEM DO SUPORTE',parent_child_links:'VÍNCULO FAMILIAR'
};
const permissionNames:Record<string,string>={
 view_archives:'Visualizar Arquivados',view_audit:'Visualizar auditoria',manage_users:'Gerenciar usuários',
 create_scales:'Criar escalas',edit_coroinha:'Editar escalas dos Coroinhas',
 edit_cerimoniario:'Editar escalas dos Cerimoniários',delete_scales:'Excluir escalas',
 send_notifications:'Enviar notificações',send_popup:'Publicar avisos na tela',
 manage_polls:'Gerenciar enquetes e perguntas',view_reports:'Visualizar relatórios',
 approve_requests:'Aprovar solicitações',attendance:'Registrar presença',
 request_service:'Solicitar participação',confirm_assignment:'Confirmar escala',
 unassign_self:'Desmarcar escala',read_notifications:'Ler notificações',
 view_scales:'Visualizar escalas',vote_polls:'Responder enquetes',view_child_scales:'Acompanhar escalas vinculadas',
 send_suggestions:'Enviar sugestões e reclamações',manage_guides:'Gerenciar orientações e funções',
 manage_fixed_rules:'Gerenciar escala automática',view_developer_panel:'Consultar painel do desenvolvedor',
 publish_updates:'Publicar atualizações'
};
const automationNames:Record<string,string>={
 archive_retention:'Arquivamento e exclusão automática de registros antigos',
 auto_approval_3h:'Aprovação automática de solicitações após 3 horas',
 notify_assignment_events:'Notificações sobre atribuições e confirmações de escalas',
 notify_coordinator_messages:'Notificações de mensagens à coordenação',
 notify_profile_approved:'Notificações de cadastro aprovado',
 notify_profile_pending:'Notificações de cadastro aguardando aprovação',
 notify_service_requests:'Notificações de pedidos para servir',
 poll_dispatch:'Envio automático das enquetes',
 push_queue:'Envio das notificações para os aparelhos'
};
const statusNames:Record<string,string>={
 escalado:'escalado',confirmado:'confirmado',desmarcado:'desmarcado',faltou:'faltou',
 presente:'presente',pendente:'pendente',aprovado:'aprovado',recusado:'recusado'
};
const groupName=(g:unknown)=>g==='cerimoniario'?'Cerimoniários':g==='coroinha'?'Coroinhas':g==='pai'?'Responsáveis':g==='coordenadora'?'Coordenadores':'integrantes';
const clean=(v:unknown,max=170)=>typeof v==='string'?v.trim().slice(0,max):'';
const quote=(v:unknown)=>clean(v)?'“'+clean(v)+'”':'(sem título)';
const date=(v:unknown)=>{if(!v)return '';const d=new Date(String(v));return Number.isNaN(d.getTime())?'':d.toLocaleString('pt-BR',{timeZone:'America/Sao_Paulo',day:'2-digit',month:'2-digit',year:'numeric',hour:'2-digit',minute:'2-digit',second:'2-digit'});};
function notificationActivity(row:AuditEntry):'archived'|'read'|null{
 if(row.table_name!=='notifications'||row.action!=='UPDATE')return null;
 const before=row.before_data||{},after=row.after_data||{};
 if(!before.archived_at&&Boolean(after.archived_at))return 'archived';
 if(before.seen!==true&&after.seen===true&&!after.archived_at)return 'read';
 return null;
}
export function groupAuditEntries(rows:AuditEntry[]):AuditEntry[]{
 const groups=new Map<string,AuditEntry>();
 // Chronological scan ensures consecutive related actions are collapsed into a
 // single short activity session, without conflating separate days or actors.
 const ordered=[...rows].sort((a,b)=>Date.parse(a.happened_at)-Date.parse(b.happened_at)||Number(a.id)-Number(b.id));
 const sessions=new Map<string,{key:string;start:number;last:number}>();
 for(const row of ordered){
  if(row.table_name==='permission_rules'){
   const before=row.before_data||{},after=row.after_data||{};
   const data=row.action==='DELETE'?before:after;
   const revoked=row.action==='DELETE'||(row.action==='UPDATE'&&Boolean(before.expires_at)&&String(after.expires_at)!==String(before.expires_at)&&
     Date.parse(String(after.expires_at))<=Date.parse(row.happened_at)+1000);
   const batch=clean(after.batch_id||before.batch_id)||('legacy:'+row.happened_at);
   const key=JSON.stringify(['permissions',batch,row.action,row.actor_id||row.actor_email||'system',
     data.subject_user||data.subject_role||'',revoked]);
   const permission={key:clean(data.permission_key),allowed:data.allowed===true,revoked};
   const previous=groups.get(key);
   if(previous){if(!(previous.permission_details||[]).some(x=>x.key===permission.key)){previous.permission_details=[...(previous.permission_details||[]),permission];previous.permission_count=(previous.permission_count||1)+1;}}
   else groups.set(key,{...row,permission_details:[permission],permission_count:1});
   continue;
  }
  const activity=notificationActivity(row);
  if(activity&&row.actor_id){
   const moment=Date.parse(row.happened_at);
   const sessionKey=JSON.stringify([row.actor_id,row.table_name,activity]);
   const session=sessions.get(sessionKey);
   // Up to 90 seconds between actions, 5 minutes max per activity session.
   const eligible=session&&Number.isFinite(moment)&&moment-session.last<=90000&&moment-session.start<=300000;
   const key=eligible?session.key:'activity:'+String(row.id);
   const detail={id:String(row.record_id||row.id),title:clean((row.after_data||row.before_data||{}).title)||'Notificação sem título',at:row.happened_at};
   const prior=groups.get(key);
   if(prior){
    prior.activity_details=[...(prior.activity_details||[]),detail];
    prior.activity_count=(prior.activity_count||1)+1;
    prior.activity_ended_at=row.happened_at;
    prior.happened_at=row.happened_at;
   }else{
    groups.set(key,{...row,activity_kind:activity,activity_details:[detail],
      activity_count:1,activity_started_at:row.happened_at,activity_ended_at:row.happened_at});
   }
   sessions.set(sessionKey,{key,start:eligible?session.start:moment,last:moment});
   continue;
  }
  if(row.table_name!=='notifications'){groups.set('id:'+row.id,{...row});continue}
  const data=row.action==='DELETE'?row.before_data||{}:row.after_data||{};
  const second=String(row.happened_at).slice(0,19);
  const key=JSON.stringify([row.table_name,row.action,row.actor_id||row.actor_email||'system',
    second,data.group_id||'',data.title||'',data.body||'',data.event_key||'']);
  const existing=groups.get(key);
  if(existing)existing.recipient_count=(existing.recipient_count||1)+1;
  else groups.set(key,{...row,recipient_count:1});
 }
 return [...groups.values()].sort((a,b)=>Date.parse(b.happened_at)-Date.parse(a.happened_at)||Number(b.id)-Number(a.id));
}
export function formatAuditEntry(row:AuditEntry){
 const before=row.before_data||{},after=row.after_data||{};
 const v=row.action==='DELETE'?before:after;
 const isAutomatic=!row.actor_id;
 const who=clean(row.actor_name)||clean(row.actor_email)||'O sistema';
 const actor=isAutomatic?'Sistema ou operação administrativa':who;
 const verb=row.action==='INSERT'?'CRIADO':row.action==='DELETE'?'EXCLUÍDO':'ATUALIZADO';
 const permissionRevoked=row.table_name==='permission_rules'&&Boolean(row.permission_details?.[0]?.revoked);
 const title=row.activity_kind&&row.activity_count&&row.activity_count>1
  ?(row.activity_kind==='archived'?'ARQUIVADAS':'LIDAS')+' — '+row.activity_count+' NOTIFICAÇÕES'
  :row.table_name==='permission_rules'&&row.permission_count&&row.permission_count>1
  ?(permissionRevoked?'REVOGADAS':'CONFIGURADAS')+' — '+row.permission_count+' PERMISSÕES'
  :permissionRevoked?'REVOGADA — PERMISSÃO':verb+' — '+(kinds[row.table_name]||'REGISTRO DO SISTEMA');
 const changed=(k:string)=>JSON.stringify(before[k])!==JSON.stringify(after[k]);
 const mass=quote(row.related_mass_name);
 const subject=quote(v.title||v.name||v.question||v.function_name||v.version);
 let detail='';
 switch(row.table_name){
 case 'masses':
  detail=row.action==='INSERT'?who+' criou a escala '+quote(v.title)+'.'+(v.starts_at?' Celebração: '+date(v.starts_at)+'.':''):
   row.action==='DELETE'?actor+' excluiu a escala '+quote(v.title)+'.':
   changed('archived_at')&&after.archived_at?actor+' arquivou a escala '+quote(v.title)+'.':
   who+' alterou a escala '+quote(v.title)+'.'+(changed('starts_at')?' Novo horário: '+date(after.starts_at)+'.':'');
  break;
 case 'assignments':
  detail=who+' '+(row.action==='INSERT'?'adicionou':row.action==='DELETE'?'removeu':'atualizou')+
    ' a função '+quote(v.function_name)+' na escala '+mass+', do grupo de '+groupName(v.service_group)+'.';
  if(row.action==='UPDATE'&&changed('status'))detail+=' Situação: '+(statusNames[String(before.status)]||clean(before.status))+
   ' → '+(statusNames[String(after.status)]||clean(after.status))+'.';
  if(row.action==='UPDATE'&&changed('server_id'))detail+=' A pessoa escalada foi alterada.';
  break;
 case 'notifications':{
  if(row.activity_kind&&row.activity_count&&row.activity_count>1){
   const details=row.activity_details||[];
   const names=[...new Set(details.map(d=>d.title))];
   detail=who+' '+(row.activity_kind==='archived'?'arquivou ':'marcou como lidas ')+
     row.activity_count+' notificações entre '+date(row.activity_started_at)+' e '+date(row.activity_ended_at)+'. '+
     'Títulos: '+names.map(n=>quote(n)).join('; ')+'.';
   break;
  }
  const qty=row.recipient_count||1;
  const intro=isAutomatic?'O sistema registrou':who+(row.action==='INSERT'?' enviou':row.action==='UPDATE'?' atualizou':' excluiu');
  if(row.action==='UPDATE'&&changed('seen')&&after.seen===true)detail=who+' marcou a notificação '+quote(v.title)+' como lida.';
  else if(row.action==='UPDATE'&&changed('archived_at')&&after.archived_at)detail=who+' arquivou a notificação '+quote(v.title)+'.';
  else detail=intro+' '+(row.action==='INSERT'?'a notificação ':'a notificação ')+quote(v.title)+
   (qty>1?' para '+qty+' destinatários':'')+'.'+(clean(v.body)?' Mensagem: '+quote(v.body)+'.':'');
  break;
 }
 case 'profiles':
  detail=row.action==='INSERT'?'Foi solicitado um cadastro para '+(clean(v.name)||clean(v.email)||'uma pessoa')+'.':
   row.action==='DELETE'?actor+' excluiu a conta de '+(clean(v.name)||clean(v.email)||'um usuário')+'.':
   changed('approved')?who+(after.approved?' aprovou':' suspendeu a aprovação de')+' a conta de '+(clean(v.name)||clean(v.email)||'um usuário')+'.':
   changed('role')?who+' alterou o perfil de '+(clean(v.name)||clean(v.email)||'um usuário')+' para '+groupName(after.role)+'.':
   who+' atualizou o cadastro de '+(clean(v.name)||clean(v.email)||'um usuário')+'.';
  break;
 case 'permission_rules':{
  const perms=row.permission_details||[{key:clean(v.permission_key),allowed:v.allowed===true,revoked:permissionRevoked}];
  const count=perms.length;
  const person=row.related_user_name?' para '+row.related_user_name:'';
  const labels=perms.map(p=>(permissionNames[p.key]||p.key)+(p.revoked?'':p.allowed?' (permitida)':' (bloqueada)'));
  detail=who+(permissionRevoked?' revogou ':count>1?' configurou ':' definiu ')+
    (count>1?count+' permissões':'a permissão')+person+': '+labels.join('; ')+'.'+
    (!permissionRevoked&&v.expires_at?' Validade até '+date(v.expires_at)+'.':'');
  break;
 }
 case 'requests':
  detail=who+' '+(row.action==='INSERT'?'enviou':row.action==='DELETE'?'removeu':'atualizou')+
   ' uma solicitação para '+(v.type==='substituir'?'substituir':'servir')+' na escala '+mass+'.'+
   (row.action==='UPDATE'&&changed('status')?' Nova situação: '+(statusNames[String(after.status)]||clean(after.status))+'.':'');
  break;
 case 'guides':
  detail=who+' '+(row.action==='INSERT'?'criou':row.action==='DELETE'?'excluiu':'atualizou')+
    ' as orientações '+(clean(v.function_name).startsWith('__como_usar_')?'de como usar o site':quote(v.function_name))+'.'+
    (clean(v.instructions)?' Conteúdo: '+quote(v.instructions)+'.':'');
  break;
 case 'service_settings':
  detail=actor+' '+(row.action==='DELETE'?'removeu':'configurou')+' a automação '+quote(automationNames[clean(v.key)]||'Configuração interna do sistema')+
   (v.enabled===undefined?'':v.enabled?' como ativada.':' como desativada.');
  break;
 case 'site_updates':
  detail=who+' '+(row.action==='INSERT'?'publicou':row.action==='DELETE'?'removeu':'editou')+
   ' a atualização '+quote(v.title)+' do site'+(v.version?' (versão '+clean(v.version)+')':'')+'.';
  break;
 case 'messages':
  detail=who+' '+(row.action==='INSERT'?'enviou':row.action==='DELETE'?'excluiu':'atualizou')+
   ' uma mensagem'+(clean(v.type)?' do tipo '+clean(v.type):'')+'.';
  break;
 case 'open_questions':
  detail=who+' '+(row.action==='INSERT'?'publicou':row.action==='DELETE'?'removeu':'alterou')+
   ' a caixinha de perguntas '+quote(v.question)+'.';
  break;
 default:
  detail=actor+' '+(row.action==='INSERT'?'criou':row.action==='DELETE'?'excluiu':'atualizou')+
   ' um registro de '+(kinds[row.table_name]||'operação do sistema').toLowerCase()+'.';
 }
 return {title,actor,detail,when:date(row.happened_at),recipientCount:row.recipient_count||1};
}
