export type AuditEntry = {
 id:number|string;happened_at:string;actor_id?:string|null;actor_email?:string|null;actor_name?:string|null;
 table_name:string;action:'INSERT'|'UPDATE'|'DELETE';record_id?:string|null;
 before_data?:Record<string,unknown>|null;after_data?:Record<string,unknown>|null;
 related_mass_name?:string|null;recipient_count?:number;
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
export function groupAuditEntries(rows:AuditEntry[]):AuditEntry[]{
 const groups=new Map<string,AuditEntry>();
 for(const row of rows){
  // Only combine copies of the SAME notification operation to different recipients.
  // Other tables, including mass editing and permissions, always retain separate actions.
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
 const title=verb+' — '+(kinds[row.table_name]||'REGISTRO DO SISTEMA');
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
 case 'permission_rules':
  detail=who+' '+(row.action==='DELETE'?'revogou':row.action==='INSERT'?'definiu':'alterou')+
    ' a permissão '+quote(permissionNames[clean(v.permission_key)]||clean(v.permission_key))+
    ' como '+(v.allowed===true?'permitida':'bloqueada')+
    (v.expires_at?', até '+date(v.expires_at):', sem prazo de expiração')+'.';
  break;
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
