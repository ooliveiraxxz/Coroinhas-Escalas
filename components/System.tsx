'use client';
import {useEffect,useState} from 'react';
import {createPortal} from 'react-dom';
import NeonLogin from './NeonLogin';
import SupportChat from './SupportChat';
import {getSupabase} from '@/lib/supabase';
import {Home,CalendarDays,Users,ChartColumn,Menu,Bell,LogOut,X,Plus,Download,BookOpen,Settings,MessageCircle,UserCircle,Church,CalendarCheck,ChevronRight,Heart,ShieldCheck,Eye,EyeOff} from 'lucide-react';
import type {SupabaseClient} from '@supabase/supabase-js';
type AnyRow=Record<string,any>;
const functions=['Missal','Cruz','Turíbulo','Círio 1','Círio 2','Ofertório 1','Ofertório 2','Book','Acolhimento'];
const fmt=(v:string)=>new Date(v).toLocaleString('pt-BR',{timeZone:'America/Sao_Paulo',dateStyle:'short',timeStyle:'short'});
const day=(v:string)=>new Date(v).toLocaleDateString('en-CA',{timeZone:'America/Sao_Paulo'});
const nowday=()=>new Date().toLocaleDateString('en-CA',{timeZone:'America/Sao_Paulo'});
const month=(v:string)=>v.slice(0,7);
type NotificationOption={key:string;label:string;future?:boolean};
const notificationOptions:Record<string,NotificationOption[]>={
 coordenadora:[
  {key:'coord_new_accounts',label:'Novo cadastro aguardando aprovação'},
  {key:'coord_messages',label:'Mensagens enviadas por coroinhas'},
  {key:'coord_requests',label:'Pedidos para servir ou substituir'},
  {key:'coord_responses',label:'Confirmações e desmarcações de escala'},
  {key:'general',label:'Avisos gerais do aplicativo'},
  {key:'support_replies',label:'Respostas do chat de suporte'}
 ],
 coroinha:[
  {key:'server_assignments',label:'Quando eu for escalado em uma missa'},
  {key:'server_substitutes',label:'Solicitações de substituto'},
  {key:'server_approval',label:'Meu cadastro aprovado'},
  {key:'general',label:'Avisos gerais do aplicativo'},
  {key:'support_replies',label:'Respostas do chat de suporte'}
 ],
 pai:[
  {key:'parent_assignments',label:'Meu filho entrar em uma escala',future:true},
  {key:'parent_withdrawals',label:'Meu filho desmarcar uma escala',future:true},
  {key:'parent_confirmations',label:'Meu filho confirmar uma escala',future:true},
  {key:'general',label:'Avisos gerais do aplicativo'},
  {key:'support_replies',label:'Respostas do chat de suporte'}
 ],
 cerimoniario:[
  {key:'ceremony_assignments',label:'Quando eu for escalado',future:true},
  {key:'ceremony_substitutes',label:'Solicitações de substituto',future:true},
  {key:'ceremony_approval',label:'Meu cadastro aprovado',future:true},
  {key:'general',label:'Avisos gerais do aplicativo'},
  {key:'support_replies',label:'Respostas do chat de suporte'}
 ],
 desenvolvedor:[
  {key:'general',label:'Avisos gerais do aplicativo'},
  {key:'support_replies',label:'Respostas do chat de suporte'},
  {key:'developer_support',label:'Novas solicitações e respostas do chat de suporte'},
  {key:'developer_system',label:'Alertas administrativos e do sistema',future:true}
 ]
};

// Auditoria em linguagem simples: mantém o histórico original intacto no Neon.
const auditTables:Record<string,string>={
 profiles:'conta de usuário',guides:'orientação de serviço',fixed_rules:'regra de escala',
 masses:'missa ou celebração',assignments:'função da escala',requests:'solicitação de escala',
 notifications:'notificação',site_updates:'atualização do aplicativo',
 messages:'mensagem',screen_announcements:'aviso na tela',
 screen_announcement_dismissals:'preferência de aviso',push_subscriptions:'notificações do aparelho',
 banned_emails:'bloqueio de e-mail',login_events:'registro de acesso'
};
const auditFields:Record<string,string>={
 name:'Nome',email:'E-mail',role:'Tipo de usuário',approved:'Aprovação',
 notes:'Observações',photo_url:'Foto de perfil',notification_preferences:'Preferências de notificações',
 title:'Título',body:'Mensagem',description:'Descrição',version:'Versão',
 function_name:'Função',instructions:'Orientações',location:'Local',
 starts_at:'Data e horário',celebrant:'Celebrante',published:'Publicação',
 status:'Situação',reason:'Justificativa',seen:'Leitura',active:'Ativação',
 target_role:'Público destinatário',display_mode:'Frequência do aviso',
 weekday:'Dia da semana',hour:'Hora',minute:'Minuto',type:'Tipo de solicitação'
};
const ignoredAuditFields=new Set(['id','created_at','updated_at','read_at','last_seen_at','user_id','created_by','server_id','mass_id','assignment_id','target_user_id','group_id','endpoint','p256dh','auth']);
function readableAuditValue(key:string,value:any):string{
 if(value===null||value===undefined||value==='')return 'Não informado';
 if(typeof value==='boolean')return key==='approved'?(value?'Aprovado':'Aguardando aprovação'):(value?'Sim':'Não');
 if(key==='role'||key==='target_role'){
  return ({coroinha:'Coroinha',pai:'Pai ou responsável',coordenadora:'Coordenador(a)',desenvolvedor:'Desenvolvedor',cerimoniario:'Cerimoniário',all:'Todos',individual:'Pessoa específica'} as Record<string,string>)[String(value)]||'Outro perfil';
 }
 if(key==='notification_preferences')return 'Preferências de notificação alteradas';
 if(key==='function_name'&&typeof value==='string'&&value.startsWith('__')){
  const role=value.match(/__como_usar_(desenvolvedor|coordenadora|coroinha|pai)/);
  if(role)return 'Orientações para '+({desenvolvedor:'desenvolvedor',coordenadora:'coordenação',coroinha:'coroinhas',pai:'pais e responsáveis'} as Record<string,string>)[role[1]];
  return 'Orientação interna';
 }
 if(key==='starts_at'){const d=new Date(value);return isNaN(d.getTime())?'Data atualizada':d.toLocaleString('pt-BR',{timeZone:'America/Sao_Paulo'});}
 if(typeof value==='object')return 'Configuração atualizada';
 const v=String(value);
 if(/^[0-9a-f]{8}-[0-9a-f-]{27,}$/i.test(v))return 'Referência interna';
 return v.length>180?v.slice(0,177)+'…':v;
}
function summarizeAudit(row:AnyRow){
 const kind=auditTables[row.table_name]||'registro do sistema';
 const action=row.action==='INSERT'?'Criado':row.action==='DELETE'?'Excluído':'Atualizado';
 const before=row.before_data&&typeof row.before_data==='object'?row.before_data:{};
 const after=row.after_data&&typeof row.after_data==='object'?row.after_data:{};
 const record=row.action==='DELETE'?before:after;
 // Referências internas como __como_usar_desenvolvedor_<uuid> não são nomes para exibir.
 const rawSubject=String(record.name||record.title||record.email||'').trim();
 const cleanSubject=rawSubject&&!/^(?:__|[0-9a-f]{8}-)/i.test(rawSubject)&&!/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}/i.test(rawSubject)
   ?rawSubject.slice(0,65):'';
 const title=action+' — '+kind+(cleanSubject?': '+cleanSubject:'');
 let details:string[]=[];
 if(row.action==='UPDATE'){
  details=Object.keys({...before,...after}).filter(k=>!ignoredAuditFields.has(k)&&JSON.stringify(before[k])!==JSON.stringify(after[k]))
   .map(k=>auditFields[k]?'**'+auditFields[k]+'**: de '+readableAuditValue(k,before[k])+' para '+readableAuditValue(k,after[k]):'Outra informação do registro foi alterada');
 }else{
  details=Object.keys(record).filter(k=>!ignoredAuditFields.has(k)&&auditFields[k])
   .filter(k=>!['name','title','email','function_name'].includes(k)&&record[k]!==null&&record[k]!==undefined&&record[k]!=='')
   .slice(0,5).map(k=>auditFields[k]+': '+readableAuditValue(k,record[k]));
 }
 if(details.length===0)details=[row.action==='INSERT'?'Um novo registro foi adicionado.':row.action==='DELETE'?'Este registro foi removido.':'Informações administrativas do registro foram alteradas.'];
 return {title,details:details.map(d=>d.replaceAll('**',''))};
}
function friendlyAppError(value:unknown){
 const raw=typeof value==='string'?value:value&&typeof value==='object'&&'message' in value?String((value as {message:unknown}).message):'';
 const message=raw.toLowerCase();
 if(!raw)return 'Não foi possível concluir a operação. Tente novamente.';
 if(/permission denied|row-level security|not authorized|forbidden|access denied/.test(message))return 'Você não tem permissão para realizar esta ação.';
 if(/duplicate key|already exists|unique constraint/.test(message))return 'Este registro já existe. Verifique os dados informados.';
 if(/foreign key|violates foreign key/.test(message))return 'Este registro está vinculado a outras informações e não pode ser alterado dessa forma.';
 if(/network|failed to fetch|fetch failed|timeout/.test(message))return 'Não foi possível conectar ao servidor. Verifique sua internet e tente novamente.';
 if(/not found|no rows/.test(message))return 'O registro solicitado não foi encontrado. Atualize a página.';
 if(/invalid login|invalid credentials|wrong password/.test(message))return 'E-mail ou senha incorretos.';
 if(/homologaç|migration/.test(message))return 'Não foi possível concluir esta operação. Atualize o aplicativo e tente novamente.';
 if(/[A-Za-z]{2,}Error:|SQLSTATE|PGRST[0-9]|[0-9A-F]{8}-[0-9A-F-]{27,}/i.test(raw))return 'Não foi possível concluir esta operação. Verifique os dados e tente novamente.';
 return raw;
}
export default function System(){
 const [legacyTargets,setLegacyTargets]=useState<Record<string,string>>({}),[notificationDraft,setNotificationDraft]=useState<Record<string,boolean>>({}),[notificationSaved,setNotificationSaved]=useState(false),[pushEnabled,setPushEnabled]=useState(false),[pushBusy,setPushBusy]=useState(false),[authLoading,setAuthLoading]=useState(true),[profileLoading,setProfileLoading]=useState(true),[db,setDb]=useState<SupabaseClient|null>(null),[user,setUser]=useState<any>(null),[profile,setProfile]=useState<AnyRow|null>(null),[error,setError]=useState(''),[busy,setBusy]=useState(false),[register,setRegister]=useState(false),[recovering,setRecovering]=useState(false),[newPassword,setNewPassword]=useState(''),[showPassword,setShowPassword]=useState(false),[showNewPassword,setShowNewPassword]=useState(false),[requestedRole,setRequestedRole]=useState<'coroinha'|'pai'>('coroinha'),[usage,setUsage]=useState<AnyRow|null>(null),[usersRole,setUsersRole]=useState('coroinha'),[accessRole,setAccessRole]=useState('coroinha'),[accessRows,setAccessRows]=useState<AnyRow[]>([]),[accessLoading,setAccessLoading]=useState(false),[accessError,setAccessError]=useState(''),[updates,setUpdates]=useState<AnyRow[]>([]),[auditRows,setAuditRows]=useState<AnyRow[]>([]),[auditFilter,setAuditFilter]=useState('todos'),[updateId,setUpdateId]=useState(''),[updateForm,setUpdateForm]=useState({version:'',title:'',description:''}),[helpTarget,setHelpTarget]=useState('coroinha'),[helpText,setHelpText]=useState(''),[helpEditTarget,setHelpEditTarget]=useState(''),[email,setEmail]=useState(''),[password,setPassword]=useState(''),[name,setName]=useState(''),[profileNameDraft,setProfileNameDraft]=useState<string|null>(null),[view,setView]=useState('Início'),[massReturnView,setMassReturnView]=useState('Início'),[pdfDocument,setPdfDocument]=useState<{url:string;blob:Blob;filename:string}|null>(null),[pdfBusy,setPdfBusy]=useState(false),[drawer,setDrawer]=useState(false),[masses,setMasses]=useState<AnyRow[]>([]),[assignments,setAssignments]=useState<AnyRow[]>([]),[profiles,setProfiles]=useState<AnyRow[]>([]),[notices,setNotices]=useState<AnyRow[]>([]),[sentNotices,setSentNotices]=useState<AnyRow[]>([]),[requests,setRequests]=useState<AnyRow[]>([]),[requestFunctions,setRequestFunctions]=useState<Record<string,string>>({}),[guides,setGuides]=useState<AnyRow[]>([]),[messages,setMessages]=useState<AnyRow[]>([]),[rules,setRules]=useState<AnyRow[]>([]),[selected,setSelected]=useState(''),[chosenMonth,setChosenMonth]=useState(nowday().slice(0,7)),[massForm,setMassForm]=useState({title:'',date:'',time:'',location:'',celebrant:'',notes:''}),[roles,setRoles]=useState<{fn:string;uid:string}[]>([]),[editId,setEditId]=useState(''),[guideForm,setGuideForm]=useState({function_name:'',instructions:'',notes:''}),[ruleForm,setRuleForm]=useState({server_id:'',weekday:'0',hour:'19',minute:'0',function_name:'',location:''}),[screenPopup,setScreenPopup]=useState<AnyRow|null>(null),[screenOptOut,setScreenOptOut]=useState(false),[screenKind,setScreenKind]=useState('message'),[screenRepeat,setScreenRepeat]=useState('optional'),[screenRole,setScreenRole]=useState('all'),[screenTarget,setScreenTarget]=useState(''),[screenSent,setScreenSent]=useState<AnyRow[]>([]),[noticeTitle,setNoticeTitle]=useState(''),[noticeBody,setNoticeBody]=useState(''),[noticeTarget,setNoticeTarget]=useState('coroinha'),[noticeEditor,setNoticeEditor]=useState(''),[noticeRecipients,setNoticeRecipients]=useState<AnyRow[]>([]),[messageBody,setMessageBody]=useState(''),[messageType,setMessageType]=useState('reclamacao'),[supportTarget,setSupportTarget]=useState(''),[supportChatOpen,setSupportChatOpen]=useState(false);
 const developer=profile?.approved===true&&profile?.role==='desenvolvedor';
 const parent=profile?.approved===true&&profile?.role==='pai';
 const coord=profile?.approved===true&&(profile?.role==='coordenadora'||developer);
 const campaigns=sentNotices.filter(n=>n.group_id).reduce((acc:AnyRow[],n:AnyRow)=>acc.some(x=>x.group_id===n.group_id)?acc:[...acc,n],[]);
 async function refresh(client=db,usr=user){if(!client||!usr)return;setProfileLoading(true);try{
  const p=await client.from('profiles').select('*').eq('id',usr.id).maybeSingle();if(p.error)throw p.error;setProfile(p.data);if(!p.data?.approved)return;
  const queries=await Promise.all([client.from('masses').select('*').order('starts_at'),client.from('assignments').select('*'),client.from('profiles').select('*'),client.from('notifications').select('*').eq('user_id',usr.id).order('created_at',{ascending:false}).limit(80),client.from('requests').select('*'),client.from('guides').select('*'),client.from('messages').select('*'),client.from('fixed_rules').select('*'),p.data.role==='coordenadora'||p.data.role==='desenvolvedor'?client.from('notifications').select('*').not('group_id','is',null).order('created_at',{ascending:false}).limit(400):Promise.resolve({data:[],error:null}),client.from('site_updates').select('*').order('published_at',{ascending:false})]);
  const setters=[setMasses,setAssignments,setProfiles,setNotices,setRequests,setGuides,setMessages,setRules,setSentNotices,setUpdates];queries.forEach((r,i)=>{if(r.error)console.warn(r.error.message);else setters[i](r.data||[])});
 }catch(e:any){setError(e.message||String(e))}finally{setProfileLoading(false)}}
 useEffect(()=>{let live=true;try{const client=getSupabase();setDb(client);client.auth.getSession().then(({data})=>{if(live){setUser(data.session?.user||null);setAuthLoading(false)}}).catch(e=>{if(live){setError(friendlyAppError(e));setAuthLoading(false)}});const {data:{subscription}}=client.auth.onAuthStateChange((_e,s)=>{if(live){if(_e==='PASSWORD_RECOVERY')setRecovering(true);setUser(s?.user||null);setAuthLoading(false)}});return()=>{live=false;subscription.unsubscribe()}}catch(e:any){setError(friendlyAppError(e));setAuthLoading(false)}},[]);
 useEffect(()=>{if(user&&db){refresh(db,user);db.rpc('record_site_access',{p_login:false}).then(()=>{});const tick=setInterval(()=>db.rpc('record_site_access',{p_login:false}).then(()=>{}),180000);return()=>clearInterval(tick)}else{setProfile(null);setProfileLoading(false)}},[user?.id,db]);
 useEffect(()=>{
  if(!db||!user?.id||!profile?.approved)return;
  let alive=true;
  const fetchAlerts=async()=>{
   const result=await db.from('notifications').select('*').eq('user_id',user.id).order('created_at',{ascending:false}).limit(80);
   if(alive&&!result.error)setNotices(result.data||[]);
  };
  void fetchAlerts();
  const timer=setInterval(()=>void fetchAlerts(),15000);
  return()=>{alive=false;clearInterval(timer)};
 },[db,user?.id,profile?.approved]);
 async function activatePush(){
  if(!db||!user)return;
  if(!('serviceWorker' in navigator)||!('PushManager' in window)||!('Notification' in window)){setError('Este navegador não suporta notificações push. No iPhone, adicione o aplicativo à Tela de Início e abra por lá.');return;}
  setPushBusy(true);setError('');
  try{
   const permission=await Notification.requestPermission();
   if(permission!=='granted')throw new Error('Notificações não autorizadas. Habilite nas configurações do celular.');
   const worker=await navigator.serviceWorker.register('/push-sw.js',{scope:'/'});
   const activeWorker=worker.active?worker:await navigator.serviceWorker.ready;
   if(!activeWorker.active){await new Promise<void>((resolve,reject)=>{const installing=worker.installing||worker.waiting;if(!installing)return reject(new Error('O serviço de notificações ainda não está pronto. Feche e abra o aplicativo.'));const onState=()=>{if(installing.state==='activated'){installing.removeEventListener('statechange',onState);resolve()}else if(installing.state==='redundant'){installing.removeEventListener('statechange',onState);reject(new Error('Falha na ativação. Abra o aplicativo novamente.'))}};installing.addEventListener('statechange',onState);onState()})}
   const subscription=await activeWorker.pushManager.subscribe({userVisibleOnly:true,applicationServerKey:process.env.NEXT_PUBLIC_VAPID_PUBLIC_KEY||'BDov9q_DBJrHGsmcCsMSIgkXnrWFYWioUSaD77Cajavor6dQxNINg2wXjMC8EmHjg79rPZByvl_1ynRPZk2EBGI'});
   const json=subscription.toJSON();
   const {error:dbError}=await db.from('push_subscriptions').upsert({user_id:user.id,endpoint:json.endpoint,p256dh:json.keys?.p256dh,auth:json.keys?.auth,created_at:new Date().toISOString()},{onConflict:'endpoint'});
   if(dbError)throw dbError;
   setPushEnabled(true);alert('Notificações ativadas neste aparelho!');
  }catch(e:any){setError(e?.message||'Não foi possível ativar as notificações.')}finally{setPushBusy(false);}
 }
 async function deactivatePush(){
  if(!db||!user)return;setPushBusy(true);setError('');
  try{
   const worker=await navigator.serviceWorker.getRegistration('/push-sw.js');
   const subscription=await worker?.pushManager.getSubscription();
   if(subscription){const {error:dbError}=await db.from('push_subscriptions').delete().eq('endpoint',subscription.endpoint).eq('user_id',user.id);if(dbError)throw dbError;await subscription.unsubscribe();}
   setPushEnabled(false);
  }catch(e:any){setError(e?.message||'Erro ao desativar notificações.')}finally{setPushBusy(false);}
 }
 useEffect(()=>{if(!user||!('serviceWorker' in navigator))return;navigator.serviceWorker.getRegistration('/push-sw.js').then(r=>r?.pushManager.getSubscription()).then(s=>setPushEnabled(!!s)).catch(()=>{});},[user?.id]);
 useEffect(()=>{
  if(!db||!user?.id||!profile?.approved)return;
  let active=true;
  (async()=>{
   const [announcements,dismissals]=await Promise.all([
    db.from('screen_announcements').select('*').order('created_at',{ascending:false}).limit(100),
    db.from('screen_announcement_dismissals').select('announcement_id').eq('user_id',user.id)
   ]);
   if(!active)return;
   if(announcements.error||dismissals.error){console.warn('Não foi possível carregar avisos de tela:',announcements.error?.message||dismissals.error?.message);return}
   if(profile.role==='desenvolvedor')setScreenSent(announcements.data||[]);
   const dismissed=new Set((dismissals.data||[]).map(row=>row.announcement_id));
   const next=(announcements.data||[]).find(row=>row.active&&!dismissed.has(row.id)&&(row.target_role==='all'||row.target_role===profile.role||(row.target_role==='individual'&&row.target_user_id===user.id)));
   if(next){setScreenOptOut(false);setScreenPopup(next)}
  })();
  return()=>{active=false};
 },[db,user?.id,profile?.id,profile?.approved,profile?.role]);
 async function closeScreenPopup(){
  if(!screenPopup||!db||!user)return;
  const remember=screenPopup.display_mode==='once'||(screenPopup.display_mode==='optional'&&screenOptOut);
  if(remember){
   const {error}=await db.from('screen_announcement_dismissals').upsert({announcement_id:screenPopup.id,user_id:user.id},{onConflict:'announcement_id,user_id'});
   if(error){setError('Não foi possível registrar sua preferência: '+error.message);return}
  }
  setScreenPopup(null);setScreenOptOut(false);
 }
 async function sendScreenPopup(){
  if(!db||!user||!developer)return;
  if(!noticeTitle.trim()||!noticeBody.trim())return setError('Informe título e mensagem.');
  if(screenRole==='individual'&&!screenTarget)return setError('Selecione o destinatário.');
  const ok=await execute(()=>db.from('screen_announcements').insert({
   title:noticeTitle.trim(),body:noticeBody.trim(),target_role:screenRole,
   target_user_id:screenRole==='individual'?screenTarget:null,
   display_mode:screenRepeat,created_by:user.id
  }));
  if(ok){
   setNoticeTitle('');setNoticeBody('');setScreenRole('all');setScreenRepeat('optional');setScreenTarget('');
   const {data}=await db.from('screen_announcements').select('*').order('created_at',{ascending:false}).limit(100);
   if(data)setScreenSent(data);
   alert('Aviso na tela publicado.');
  }
 }
 async function disableScreenPopup(id:string){
  if(!db||!developer)return;
  const ok=await execute(()=>db.from('screen_announcements').update({active:false}).eq('id',id));
  if(ok)setScreenSent(previous=>previous.map(x=>x.id===id?{...x,active:false}:x));
 }
 async function execute(fn:()=>PromiseLike<any>){setBusy(true);setError('');try{const r=await fn();if(r?.error)throw r.error;await refresh();return true}catch(e:any){setError(friendlyAppError(e));return false}finally{setBusy(false)}}
 async function auth(){if(!db)return setError('Supabase não configurado. Configure as variáveis na Vercel.');setBusy(true);setError('');try{if(register){const {data,error}=await db.auth.signUp({email,password,options:{data:{name,requested_role:requestedRole}}});if(error)throw error;alert(data.session?'Cadastro enviado para aprovação.':'Cadastro criado! Confira seu e-mail se for solicitada confirmação.');setRegister(false)}else{const {error}=await db.auth.signInWithPassword({email,password});if(error)throw error;await db.rpc('record_site_access',{p_login:true})}}catch(e:any){setError(friendlyAppError(e))}finally{setBusy(false)}}
 async function sendNotice(){
  if(!noticeTitle.trim()||!noticeBody.trim())return setError('Informe título e mensagem.');
  const categories:Record<string,string>={coroinha:'coroinhas',pai:'pais e responsáveis',coordenadora:'coordenadores',todos:'usuários'};
  const selected=noticeTarget.startsWith('user:')?noticeTarget.slice(5):null;
  const target=selected?'individual':noticeTarget;
  const recipients=profiles.filter(p=>p.approved===true&&(target==='todos'||(target==='individual'?p.id===selected:p.role===target)));
  if(recipients.length===0){
   setError(target==='individual'?'O usuário selecionado não está aprovado.':`Não há ${categories[target]||'destinatários'} aprovados para receber esta notificação.`);
   return;
  }
  const ok=await execute(()=>db!.rpc('send_notification_targeted',{p_title:noticeTitle.trim(),p_body:noticeBody.trim(),p_target:target,p_recipient:selected}));
  if(ok){setNoticeTitle('');setNoticeBody('');setNoticeTarget('coroinha');alert('Notificação enviada para '+recipients.length+' destinatário(s).')}
 }
 async function editNotice(){if(!noticeEditor)return;const ok=await execute(()=>db!.rpc('edit_notification',{p_group:noticeEditor,p_title:noticeTitle.trim(),p_body:noticeBody.trim()}));if(ok){setNoticeEditor('');setNoticeTitle('');setNoticeBody('');alert('Aviso atualizado. Todos deverão confirmar leitura novamente.')}}
 async function deleteNotice(gid:string){if(!confirm('Apagar este aviso para todos os destinatários?'))return;await execute(()=>db!.rpc('delete_notification',{p_group:gid}));}
 async function showNoticeReaders(gid:string){if(!db)return;const {data,error}=await db.from('notifications').select('user_id,seen,read_at').eq('group_id',gid);if(error)return setError(friendlyAppError(error));setNoticeRecipients(data||[]);}
 async function signout(){
  if(!db||busy)return;
  setBusy(true);setError('');
  try{
   const result=await db.auth.signOut();
   if(result?.error)throw result.error;
   setDrawer(false);setUser(null);setProfile(null);setView('Início');
   // Reinicia a sessão e limpa os dados em memória antes de exibir o login.
   window.location.replace(window.location.origin+'/');
  }catch(e:any){setError('Não foi possível sair. '+(e?.message||'Tente novamente.'));setDrawer(false)}
  finally{setBusy(false)}
 }
 async function notifyAll(title:string,body:string,target?:string){if(!db)return;const ids=profiles.filter(p=>p.approved&&(!target||p.id===target)).map(p=>({user_id:p.id,title,body}));if(ids.length)await db.from('notifications').insert(ids)}
 const massTemplates=[
  {title:'Missa Dominical',time:'08:00',weekday:0},
  {title:'Missa Dominical',time:'19:00',weekday:0},
  {title:'Missa dos Enfermos',time:'19:30',weekday:2},
  {title:'Missa do Santíssimo',time:'08:00',weekday:4},
  {title:'Missa do Santíssimo',time:'19:30',weekday:4}
 ];
 function selectMassTemplate(index:number){
  const template=massTemplates[index];if(!template)return;
  const today=nowday();
  const candidate=new Date(today+'T12:00:00');
  const offset=(template.weekday-candidate.getDay()+7)%7;
  candidate.setDate(candidate.getDate()+offset);
  const localFmt=new Intl.DateTimeFormat('en-CA',{timeZone:'America/Sao_Paulo',year:'numeric',month:'2-digit',day:'2-digit'});
  const timeFmt=new Intl.DateTimeFormat('pt-BR',{timeZone:'America/Sao_Paulo',hour:'2-digit',minute:'2-digit',hourCycle:'h23'});
  const occupied=new Set(masses.filter(m=>m.title.trim().toLowerCase()===template.title.toLowerCase()&&timeFmt.format(new Date(m.starts_at))===template.time).map(m=>localFmt.format(new Date(m.starts_at))));
  let nextDate='';
  for(let i=0;i<520;i++){
   const iso=candidate.getFullYear()+'-'+String(candidate.getMonth()+1).padStart(2,'0')+'-'+String(candidate.getDate()).padStart(2,'0');
   if(!occupied.has(iso)){nextDate=iso;break;}
   candidate.setDate(candidate.getDate()+7);
  }
  if(!nextDate){setError('Não foi possível encontrar uma próxima data disponível.');return;}
  setError('');
  setMassForm(prev=>({...prev,title:template.title,time:template.time,date:nextDate}));
 }
 async function saveMass(){if(!db)return;if(roles.some(r=>!r.fn.trim())){setError('Preencha a função adicionada ou remova o campo vazio.');return;}await execute(async()=>{const dateISO=new Date(`${massForm.date}T${massForm.time}:00-03:00`).toISOString();const payload={title:massForm.title,starts_at:dateISO,location:massForm.location,celebrant:massForm.celebrant,notes:massForm.notes,published:true};let id=editId;if(editId){const r=await db.from('masses').update(payload).eq('id',editId);if(r.error)return r;const oldSlots=assignments.filter(a=>a.mass_id===editId);for(let i=0;i<roles.length;i++){const existing=oldSlots[i];if(existing){const changed=existing.server_id!==(roles[i].uid||null);const rr=await db.from('assignments').update({function_name:roles[i].fn,server_id:roles[i].uid||null,...(changed?{status:'escalado',reason:null}:{})}).eq('id',existing.id);if(rr.error)return rr;}else{const rr=await db.from('assignments').insert({mass_id:editId,function_name:roles[i].fn,server_id:roles[i].uid||null,status:'escalado'});if(rr.error)return rr;}}for(const extra of oldSlots.slice(roles.length)){const rr=await db.from('assignments').delete().eq('id',extra.id);if(rr.error)return rr;}await notifyAll('Escala atualizada',`${massForm.title} • ${massForm.date} ${massForm.time}`);setView('Missas');setEditId('');return {error:null}}else{const r=await db.from('masses').insert({...payload,created_by:user.id}).select('id').single();if(r.error)return r;id=r.data.id}const a=roles.map(x=>({mass_id:id,function_name:x.fn,server_id:x.uid||null,status:'escalado'}));if(a.length){const r=await db.from('assignments').insert(a);if(r.error)return r}await notifyAll('Escala cadastrada',`${massForm.title} • ${massForm.date} ${massForm.time}`);for(const r of roles.filter(x=>x.uid))await notifyAll('Você está escalado!',`${massForm.title}: ${r.fn}`,r.uid);setView('Missas');setEditId('');return {error:null}})}
 function editMass(m:AnyRow){setEditId(m.id);const d=new Date(m.starts_at);setMassForm({title:m.title,date:day(m.starts_at),time:d.toLocaleTimeString('pt-BR',{timeZone:'America/Sao_Paulo',hour:'2-digit',minute:'2-digit'}),location:m.location,celebrant:m.celebrant||'',notes:m.notes||''});setRoles(assignments.filter(a=>a.mass_id===m.id).map(a=>({fn:a.function_name,uid:a.server_id||''})));setView('Cadastrar missa')}
 const chooseMass=(m:AnyRow)=>{setMassReturnView(view);setSelected(m.id);setView('Detalhes da missa')};
 
 async function createPdfReport(items:AnyRow[],filename:string,title:string){
  if(!items.length){setError('Não há missas para incluir neste PDF.');return;}
  setPdfBusy(true);setError('');
  try{
   const {jsPDF}=await import('jspdf');
   const doc=new jsPDF({orientation:'portrait',unit:'mm',format:'a4'});
   const pageWidth=210,pageHeight=297,margin=15;
   let y=20;
   const nextPage=(needed=10)=>{if(y+needed>pageHeight-18){doc.addPage();y=20;}};
   const write=(str:string,x:number,size=11,bold=false,maxWidth=175)=>{
    doc.setFont('helvetica',bold?'bold':'normal');doc.setFontSize(size);
    const lines=doc.splitTextToSize(String(str),maxWidth) as string[];
    const h=Math.max(5,size*0.46+1);
    for(const line of lines){nextPage(h);doc.text(line,x,y);y+=h;}
   };
   doc.setTextColor(117,30,51);write('ESCALA SAO BENTO',margin,17,true);y+=2;
   doc.setTextColor(45,35,42);write(title,margin,13,true);y+=2;
   doc.setDrawColor(220,200,205);doc.line(margin,y,pageWidth-margin,y);y+=9;
   for(const m of items){
    nextPage(35);
    doc.setTextColor(117,30,51);write(String(m.title||'Missa'),margin,13,true);y+=1;
    doc.setTextColor(45,35,42);write('Data e horario: '+fmt(m.starts_at),margin,10);
    if(m.celebrant)write('Celebrante: '+String(m.celebrant),margin,10);
    if(m.notes?.trim())write('Observacoes: '+String(m.notes).trim(),margin,10);
    y+=3;
    const slots=assignments.filter(a=>a.mass_id===m.id);
    if(!slots.length){write('Nenhuma funcao cadastrada.',margin,10);y+=5;continue;}
    for(const a of slots){
     const person=a.server_id?byId(a.server_id):'Vaga aberta';
     const line=String(a.function_name||'Funcao')+' - '+person+' ('+String(a.status||'aberta')+')';
     doc.setTextColor(50,43,47);write(line,margin+3,10,false,170);
    }
    y+=9;
    nextPage(8);doc.setDrawColor(235,221,223);doc.line(margin,y,pageWidth-margin,y);y+=8;
   }
   const blob=doc.output('blob');
   const url=URL.createObjectURL(blob);
   setPdfDocument(old=>{if(old)URL.revokeObjectURL(old.url);return {url,blob,filename};});
  }catch(e:any){setError('Não foi possível gerar o PDF: '+(e?.message||String(e)));}
  finally{setPdfBusy(false);}
 }
 function exportPdf(period:'dia'|'semana'|'mes'){
  const base=selected?masses.find(m=>m.id===selected)?.starts_at:new Date().toISOString();
  const d=new Date(base||new Date());
  const filtered=masses.filter(m=>{
   const t=new Date(m.starts_at);
   if(period==='dia')return day(m.starts_at)===day(d.toISOString());
   if(period==='mes')return month(day(m.starts_at))===month(day(d.toISOString()));
   return Math.abs(t.getTime()-d.getTime())<=7*86400000;
  });
  void createPdfReport(filtered,'relatorio-escalas-'+period+'.pdf','Relatorio de escalas - '+period);
 }
 function exportMonthlyScales(){
  const selectedMasses=liveMasses.filter(m=>month(day(m.starts_at))===chosenMonth).sort((a,b)=>new Date(a.starts_at).getTime()-new Date(b.starts_at).getTime());
  void createPdfReport(selectedMasses,'escalas-'+chosenMonth+'.pdf','Escalas mensais - '+chosenMonth);
 }
 function savePdfDownload(){
  if(!pdfDocument)return;
  const link=document.createElement('a');link.href=pdfDocument.url;link.download=pdfDocument.filename;
  document.body.appendChild(link);link.click();link.remove();
 }
 async function sharePdf(){
  if(!pdfDocument)return;
  try{
   const file=new File([pdfDocument.blob],pdfDocument.filename,{type:'application/pdf'});
   if(navigator.share&&(!navigator.canShare||navigator.canShare({files:[file]}))){
    await navigator.share({files:[file],title:'Escala São Bento'});
   }else savePdfDownload();
  }catch(e:any){if(e?.name!=='AbortError')setError('Não foi possível abrir o compartilhamento: '+(e?.message||String(e)));}
 }
 function closePdf(){setPdfDocument(old=>{if(old)URL.revokeObjectURL(old.url);return null;});}
 const b=(label:string,fn:()=>void,alt=false)=> <button className={'btn '+(alt?'alt':'')} onClick={fn}>{label}</button>;
 const field=(label:string,value:string,onChange:(v:string)=>void,type='text')=><label className="field">{label}<input type={type} value={value} onChange={e=>onChange(e.target.value)}/></label>;
 const byId=(id:string)=>profiles.find(p=>p.id===id)?.name||'Coroinha';
 const prefs=profile?.notification_preferences||{enabled:true,free_slots:true,withdrawals:true,new_schedules:true};
 const roleOptions=notificationOptions[profile?.role||'coroinha']||notificationOptions.coroinha;
 useEffect(()=>{if(!profile?.id)return;setNotificationDraft({...profile.notification_preferences});setNotificationSaved(false)},[profile?.id,profile?.role,profile?.notification_preferences]);
 const saveNotificationPreferences=async()=>{
  if(!db||!user||!profile||busy)return;
  setBusy(true);setError('');setNotificationSaved(false);
  const next={...prefs,...notificationDraft};
  try{
   const {error}=await db.from('profiles').update({notification_preferences:next}).eq('id',user.id);
   if(error)throw error;
   setProfile(previous=>previous?{...previous,notification_preferences:next}:previous);
   setNotificationSaved(true);
  }catch(e:any){setError('Não foi possível salvar suas preferências: '+(e?.message||'Tente novamente.'))}
  finally{setBusy(false)}
 };
 const visibleNotices=notices.filter(n=>{
  if(prefs.enabled===false)return false;
  const eventKey=typeof n.event_key==='string'?n.event_key:'general';
  if(prefs[eventKey]===false)return false;
  if(eventKey!=='general')return true;
  return (!/vaga|substitui/i.test(n.title)||prefs.free_slots!==false)
    &&(!/desmarc|desist/i.test(n.title)||prefs.withdrawals!==false)
    &&(!/escala cadastrada|nova escala|você está escalado|escala atualizada/i.test(n.title)||prefs.new_schedules!==false);
 });
 const setAssignment=async(id:string,patch:AnyRow)=>{if(!coord||busy||!db)return;setBusy(true);setError('');try{const {data,error}=await db.from('assignments').update(patch).eq('id',id).select('*').single();if(error)throw error;if(!data)throw new Error('Nenhuma escala foi alterada.');setAssignments(previous=>previous.map(a=>a.id===id?{...a,...data}:a));alert(patch.status==='presente'?'Presença registrada com sucesso.':patch.status==='faltou'?'Falta registrada com sucesso.':'Alterações salvas com sucesso.');}catch(e:any){setError('Não foi possível salvar: '+(e?.message||String(e)));}finally{setBusy(false)}};
 const liveMasses=masses.filter(m=>m.published);
 const availableToServe=liveMasses.filter(m=>new Date(m.starts_at)>new Date()&&!assignments.some(a=>a.mass_id===m.id&&a.server_id===user?.id&&a.status!=='desmarcado')&&!requests.some(r=>r.mass_id===m.id&&r.user_id===user?.id&&r.type==='servir'&&r.status==='pendente'));
 const loadAudit=async()=>{if(!db||!developer)return;const {data,error}=await db.from('audit_log').select('*').order('happened_at',{ascending:false}).limit(250);if(error)setError(friendlyAppError(error));else setAuditRows(data||[])};
 const showDeveloper=async()=>{if(!db)return;const {data,error}=await db.rpc('developer_usage_summary');if(error)setError(friendlyAppError(error));else setUsage(data)};
 const loadRecentAccess=async(role=accessRole)=>{if(!db||!developer)return;setAccessLoading(true);setAccessError('');setAccessRole(role);try{const {data,error}=await db.rpc('developer_recent_access',{p_role:role});if(error)throw error;setAccessRows(Array.isArray(data)?data:[])}catch(e:any){setAccessError('Não foi possível consultar os acessos: '+(e?.message||String(e)));setAccessRows([])}finally{setAccessLoading(false)}};
 const cardMass=(m:AnyRow)=><div className="item" key={m.id} onClick={()=>chooseMass(m)}><div className="line"><div><b>{m.title}</b><div className="muted">{fmt(m.starts_at)} · {m.location}</div><div className="muted">{assignments.filter(a=>a.mass_id===m.id).length} funções</div></div><span className="chip">Ver →</span></div></div>;
 const quickNavLabels=coord?['Início','Missas',developer?'Usuários':'Coroinhas',developer?'Painel desenvolvedor':'Relatórios']:parent?['Início','Escalas mensais','Notificações','Perfil']:['Início','Escalas mensais','Quero servir','Notificações'];
 const menuItems=(developer?['Início','Missas','Usuários','Relatórios','Como servir','Como usar o site','Notificações','Suporte','Ajustes','Atualizações','Painel desenvolvedor','Auditoria']:coord?['Início','Missas','Coroinhas','Relatórios','Escala automática','Como servir','Como usar o site','Notificações','Mensagens','Suporte','Ajustes','Atualizações']:parent?['Início','Escalas mensais','Notificações','Como usar o site','Suporte','Ajustes','Atualizações']:['Início','Escalas mensais','Quero servir','Como servir','Como usar o site','Notificações','Suporte','Ajustes','Atualizações']).filter(label=>!quickNavLabels.includes(label));
 if(recovering)return <div className="auth"><div className="auth-brand"><div className="brand-symbol"><Church size={44}/></div><h1>Escala São Bento</h1></div><div className="auth-box"><h2>Redefinir senha</h2><p>Escolha uma nova senha para sua conta.</p><label className="field">Nova senha<div className="password-field"><input type={showNewPassword?'text':'password'} autoComplete="new-password" minLength={8} value={newPassword} onChange={e=>setNewPassword(e.target.value)}/><button type="button" className="password-toggle" onClick={()=>setShowNewPassword(v=>!v)} aria-label={showNewPassword?'Ocultar senha':'Mostrar senha'} aria-pressed={showNewPassword}>{showNewPassword?<EyeOff size={21}/>:<Eye size={21}/>}</button></div></label><button className="btn full" disabled={busy||newPassword.length<8} onClick={async()=>{if(!db)return;setBusy(true);setError('');const {error}=await db.auth.updateUser({password:newPassword});setBusy(false);if(error){setError(friendlyAppError(error));return;}setRecovering(false);setNewPassword('');alert('Senha alterada com sucesso!')}}>Salvar nova senha</button>{error&&<div className="notice error">{error}</div>}</div></div>;
 if(authLoading||(user&&!profile&&profileLoading)||(user&&!profile&&!error))return <div className="auth"><div className="auth-brand"><div className="brand-symbol"><Church size={44} strokeWidth={1.4}/></div><h1>Coroinhas</h1><p>Em tudo, servir a Deus com amor e alegria.</p></div></div>;
 if(!user&&process.env.NEXT_PUBLIC_DATA_BACKEND==='neon-migration')return <NeonLogin/>;
 if(!user||!profile?.approved)return <div className={user?'auth auth-pending':'auth'}><div className="auth-brand"><div className="brand-symbol"><Church size={44} strokeWidth={1.4}/></div><h1>Coroinhas</h1><p>Servir é amar.</p></div><div className={user?'auth-box pending-card':'auth-box'}>{!user?<><h2>{register?'Criar conta':'Entrar'}</h2>{register&&<>{field('Nome completo',name,setName)}<label className="field">Tipo de cadastro<select value={requestedRole} onChange={e=>setRequestedRole(e.target.value as 'pai'|'coroinha')}><option value="coroinha">Sou coroinha</option><option value="pai">Sou pai, mãe ou responsável</option></select></label><p className="muted">O cadastro será liberado após aprovação da coordenação.</p></>}{field('E-mail',email,setEmail,'email')}<label className="field">Senha<div className="password-field"><input type={showPassword?'text':'password'} autoComplete={register?'new-password':'current-password'} value={password} onChange={e=>setPassword(e.target.value)}/><button type="button" className="password-toggle" onClick={()=>setShowPassword(v=>!v)} aria-label={showPassword?'Ocultar senha':'Mostrar senha'} aria-pressed={showPassword}>{showPassword?<EyeOff size={21}/>:<Eye size={21}/>}</button></div></label><button className="btn full" disabled={busy} onClick={auth}>{busy?'Enviando...':register?'Solicitar acesso':'Entrar'}</button><button className="btn alt full" style={{marginTop:12}} onClick={()=>setRegister(!register)}>{register?'Já tenho conta':'Criar conta / Solicitar acesso'}</button>{!register&&<button className="btn neutral full" style={{marginTop:10}} onClick={async()=>{if(!db||!email)return setError('Informe o e-mail primeiro');const {error}=await db.auth.resetPasswordForEmail(email,{redirectTo:window.location.origin});setError(error?.message||'Se este e-mail estiver cadastrado, confira sua caixa de entrada para redefinir a senha.')}}>Esqueci minha senha</button>}</>:<><div className="pending-eyebrow">ACESSO À PLATAFORMA</div><h2>Cadastro aguardando aprovação</h2><p className="pending-description">Sua conta foi criada. Aguarde a liberação da coordenação para acessar as escalas.</p><div className="pending-actions">{b('Atualizar situação',()=>refresh())}{b('Sair',signout,true)}</div></>}{error&&<div className="notice error">{error}</div>}</div></div>;
 return <div className="app"><header className="top"><div className="toprow"><button className="avatar-trigger" aria-label="Meu perfil" onClick={()=>setView('Perfil')}><UserCircle/></button><div className="grow" style={{textAlign:'center'}}><div className="brand"><Church size={24} strokeWidth={1.5}/> Coroinhas</div><div className="subtitle">{developer?'Desenvolvedor':coord?'Coordenação':parent?'Pai/Responsável':'Servir é amar.'}</div></div><button onClick={()=>setView(coord&&!developer&&messages.some(m=>!m.seen)?'Mensagens':'Notificações')}><Bell size={22}/>{(visibleNotices.some(n=>!n.seen)||(coord&&!developer&&messages.some(m=>!m.seen)))&&'•'}</button><button onClick={()=>setDrawer(true)}><Menu/></button></div></header>
 <main className="content">{!['Início','Missas','Escalas mensais','Quero servir','Coroinhas','Usuários','Relatórios','Painel desenvolvedor'].includes(view)&&<div className="view-close-bar"><button type="button" className="view-close-button" aria-label="Fechar esta tela" onClick={()=>{setError('');setSupportTarget('');setNoticeEditor('');setUpdateId('');setView(view==='Detalhes da missa'?massReturnView:view==='Cadastrar missa'?'Missas':'Início')}}><X size={18}/> Fechar</button></div>}{error&&<div className="notice error" onClick={()=>setError('')}>{error} ✕</div>}
 {view==='Início'&&<><h2 className="title">Bem-vindo, {profile.name||'coroinha'}!</h2><p className="muted">Que bom ter você aqui. Servir é amar.</p><div className="grid2"><button className="btn" onClick={()=>{if(coord){setEditId('');setRoles([]);setMassForm({title:'',date:'',time:'',location:'',celebrant:'',notes:''});setView('Cadastrar missa')}else setView(parent?'Escalas mensais':'Quero servir')}}>{coord?'Cadastrar escala':parent?'Ver celebrações':'Quero servir neste dia'}</button><button className="btn alt" onClick={()=>setView(coord?'Missas':'Escalas mensais')}>Escalas mensais</button></div><div className="section"><h3>{coord||parent?'Próximas missas':'Suas próximas escalas'}</h3><a onClick={()=>setView(coord?'Missas':'Escalas mensais')}>Ver todas →</a></div>{liveMasses.filter(m=>new Date(m.starts_at)>=new Date(Date.now()-86400000)).filter(m=>coord||parent||assignments.some(a=>a.mass_id===m.id&&a.server_id===user.id&&a.status!=='desmarcado')).slice(0,5).map(cardMass)}{!masses.length&&<div className="card">Nenhuma missa cadastrada ainda.</div>}</>}
 {(view==='Missas'||view==='Escalas mensais'||view==='Quero servir')&&<><h2 className="title">{view}</h2>{field('Mês',chosenMonth,setChosenMonth,'month')}{coord&&<div className="monthly-export-actions">{coord&&b('+ Cadastrar missa',()=>{setEditId('');setRoles([]);setMassForm({title:'',date:'',time:'',location:'',celebrant:'',notes:''});setView('Cadastrar missa')})}{b('Gerar PDF',exportMonthlyScales,true)}</div>}{(view==='Quero servir'?availableToServe:liveMasses).filter(m=>month(day(m.starts_at))===chosenMonth).map(m=><div className="card mass-list-card" key={m.id}><div className="line"><b>{m.title}</b><span className="chip">{fmt(m.starts_at)}</span></div>{m.notes?.trim()&&<p className="muted">{m.notes.trim()}</p>}<div className="btnrow">{b('Ver escala',()=>chooseMass(m),true)}{view==='Quero servir'&&b('Quero servir',()=>execute(()=>db!.from('requests').insert({mass_id:m.id,user_id:user.id,type:'servir'})).then(ok=>ok&&alert('Pedido enviado à coordenação')))}{coord&&b('Editar',()=>editMass(m))}</div></div>)}</>}
 {view==='Detalhes da missa'&&(()=>{const m=masses.find(x=>x.id===selected);if(!m)return <p>Missa não encontrada</p>;const aa=assignments.filter(a=>a.mass_id===selected);return <><h2 className="title">{m.title}</h2><div className="card"><b>{fmt(m.starts_at)}</b>{m.notes?.trim()&&<p>{m.notes.trim()}</p>}</div><h3>Escala desta missa</h3>{aa.map(a=><div className="item" key={a.id}><div className="line"><div><b>{a.function_name}</b><div className="muted">{a.server_id?byId(a.server_id):'Vaga disponível'}</div></div><span className="chip">{!a.server_id||a.status==='desmarcado'?'Vaga aberta':a.status==='escalado'?'Aguardando confirmação':a.status==='confirmado'?'Confirmado':a.status==='presente'?'Presente':a.status==='faltou'?'Faltou':a.status}</span></div>{!coord&&a.server_id===user.id&&['escalado','confirmado'].includes(a.status)&&<div className="assignment-actions">
{<button className="btn alt" disabled={busy} onClick={()=>{const reason=prompt('Justificativa obrigatória para desmarcar (mínimo de 3 caracteres):');if(reason?.trim()&&reason.trim().length>=3)execute(()=>db!.rpc('respond_assignment',{p_id:a.id,p_action:'desmarcar',p_reason:reason.trim()}));else if(reason!==null)alert('Informe uma justificativa com pelo menos 3 caracteres.')}}>Desmarcar</button>}
<button className="btn alt" disabled={busy} onClick={()=>{const suggestion=prompt('Qual alteração você sugere para esta escala?');if(suggestion?.trim())execute(()=>db!.from('messages').insert({user_id:user.id,type:'sugestao',body:'Sugestão para '+m.title+' ('+fmt(m.starts_at)+') / '+a.function_name+': '+suggestion.trim()}))}}>Sugerir alteração</button>
{a.status==='escalado'&&day(m.starts_at)===nowday()&&new Date(m.starts_at)>new Date()&&<button className="btn assignment-confirm" disabled={busy} onClick={()=>execute(()=>db!.rpc('respond_assignment',{p_id:a.id,p_action:'confirmar',p_reason:''}))}>Confirmar escala</button>}
</div>}{!coord&&a.status==='desmarcado'&&b('Quero substituir',()=>execute(()=>db!.from('requests').insert({mass_id:m.id,assignment_id:a.id,user_id:user.id,type:'substituir'})).then(ok=>ok&&alert('Solicitação enviada ao(à) coordenador(a)')))}</div>)}{coord&&<div className="card"><h3>Gerenciar coroinhas da escala</h3>{aa.map(a=><div className="item" key={'manage'+a.id}><b>{a.function_name} — {a.server_id?byId(a.server_id):'Vaga aberta'}</b>{a.function_name==='A definir'&&a.server_id&&a.status!=='desmarcado'&&<div className="legacy-function-fix"><label className="field">Corrigir função antiga<select value={legacyTargets[a.id]||''} onChange={e=>setLegacyTargets(prev=>({...prev,[a.id]:e.target.value}))}><option value="">Selecione uma vaga aberta</option>{aa.filter(x=>x.id!==a.id&&(!x.server_id||x.status==='desmarcado')).map(x=><option value={x.id} key={x.id}>{x.function_name}</option>)}</select></label><button className="btn" disabled={!legacyTargets[a.id]||busy} onClick={async()=>{const ok=await execute(()=>db!.rpc('reassign_legacy_function',{p_old_assignment_id:a.id,p_open_assignment_id:legacyTargets[a.id]}));if(ok){setLegacyTargets(prev=>({...prev,[a.id]:''}));alert('Função corrigida na escala.')}}}>Atribuir função</button></div>}<label className="field">Coroinha<select value={a.server_id||''} onChange={e=>setAssignment(a.id,{server_id:e.target.value||null,status:'escalado',reason:null})}><option value="">Vaga aberta</option>{profiles.filter(p=>p.approved&&p.role==='coroinha').map(p=><option key={p.id} value={p.id}>{p.name}</option>)}</select></label><label className="field">Função<input defaultValue={a.function_name} key={a.id+a.function_name} onBlur={e=>{if(e.target.value.trim()&&e.target.value!==a.function_name)setAssignment(a.id,{function_name:e.target.value.trim()})}} /></label><div className="btnrow">{a.status!=='presente'&&b('Confirmar presença',()=>setAssignment(a.id,{status:'presente',reason:null}),true)}{a.status!=='faltou'&&b('Faltou',()=>setAssignment(a.id,{status:'faltou'}),true)}{b('Excluir',()=>{if(confirm('Excluir esta atribuição da escala?'))execute(()=>db!.from('assignments').delete().eq('id',a.id).select('id').single())},true)}</div></div>)}</div>}{coord&&<div className="btnrow">{b('Editar escala',()=>editMass(m))}{b('Excluir escala',()=>{if(confirm('Excluir esta missa e as escalas?'))execute(()=>db!.from('masses').delete().eq('id',m.id)).then(()=>setView('Missas'))},true)}{b('Baixar PDF',()=>exportPdf('dia'),true)}</div>}</>})()}
 {view==='Cadastrar missa'&&coord&&<><h2 className="title">{editId?'Editar':'Cadastrar'} missa</h2><div className="card">{!editId&&<label className="field">Selecionar modelo de missa<select defaultValue="" onChange={e=>{if(e.target.value!=='')selectMassTemplate(Number(e.target.value))}}><option value="">Escolha um modelo ou preencha manualmente</option>{massTemplates.map((t,i)=><option key={i} value={i}>{t.title} — {t.time.replace(':','h')} ({['Domingo','Segunda','Terça','Quarta','Quinta','Sexta','Sábado'][t.weekday]})</option>)}</select></label>}{field('Nome da missa',massForm.title,v=>setMassForm({...massForm,title:v}))}{field('Data',massForm.date,v=>setMassForm({...massForm,date:v}),'date')}{field('Horário',massForm.time,v=>setMassForm({...massForm,time:v}),'time')}{field('Observações',massForm.notes,v=>setMassForm({...massForm,notes:v}))}<h3>Funções e coroinhas escalados</h3>{roles.map((r,i)=><div className="item" key={i}><label className="field">Função<input type="text" placeholder="Ex.: Cruz, Missal, Turíbulo..." value={r.fn} onChange={e=>setRoles(roles.map((x,j)=>j===i?{...x,fn:e.target.value}:x))}/></label><label className="field">Coroinha<select value={r.uid} onChange={e=>setRoles(roles.map((x,j)=>j===i?{...x,uid:e.target.value}:x))}><option value="">Vaga aberta</option>{profiles.filter(p=>p.approved&&p.role==='coroinha').map(p=><option value={p.id} key={p.id}>{p.name}</option>)}</select></label>{b('Remover função',()=>setRoles(roles.filter((_,j)=>j!==i)),true)}</div>)}<div className="btnrow">{b('+ Adicionar função',()=>setRoles([...roles,{fn:'',uid:''}]),true)}{b(busy?'Salvando...':'Publicar escala',saveMass)}</div></div></>}
 {view==='Painel desenvolvedor'&&developer&&<>
  <h2 className="title">Painel do desenvolvedor</h2>
  <div className="card">
   <h3>Indicadores de utilização</h3>
   <p className="muted">Ativos: contas que acessaram o site nas últimas 24 horas. Logins: registros coletados desde a ativação do histórico.</p>
   {usage?<div className="developer-metrics">{([
    ['Usuários',usage.total_users],['Aprovados',usage.approved_users],['Pendentes',usage.pending_users],
    ['Coroinhas',usage.servers],['Responsáveis',usage.parents],['Coordenadores(as)',usage.coordinators],
    ['Desenvolvedores',usage.developers],['Ativos (24h)',usage.active_24h],['Logins registrados',usage.logins_recorded],
    ['Missas',usage.masses],['Notificações',usage.notifications],['Banco em MB',((Number(usage.db_size_bytes)||0)/1048576).toFixed(2)]
   ] as [string,string|number][]).map(([label,value])=><div className="metric" key={label}><strong>{value??0}</strong><small>{label}</small></div>)}</div>
   :<p className="muted">Toque em Atualizar indicadores para carregar os dados.</p>}
   <div className="developer-report-action">{b('Atualizar indicadores',showDeveloper)}</div>
  </div>
  <div className="card">
   <h3>Últimos acessos por perfil</h3>
   <p className="muted">Consulte as contas aprovadas, seus e-mails e o último acesso registrado.</p>
   <label className="field">Tipo de usuário
    <select value={accessRole} onChange={e=>void loadRecentAccess(e.target.value)}>
     <option value="coroinha">Coroinhas</option>
     <option value="pai">Pais e responsáveis</option>
     <option value="coordenadora">Coordenadores(as)</option>
    </select>
   </label>
   <button className="btn alt full" type="button" disabled={accessLoading} onClick={()=>void loadRecentAccess()}>{accessLoading?'Consultando…':'Atualizar acessos'}</button>
   {accessError&&<div className="notice error" role="alert">{accessError}</div>}
   {!accessLoading&&!accessError&&accessRows.length===0&&<p className="muted developer-access-empty">Nenhuma pessoa aprovada neste perfil.</p>}
   <div className="developer-access-list" style={{display:'grid',gridTemplateColumns:'minmax(0,1fr)',gap:12,marginTop:16}}>
    {accessRows.map((entry,i)=><article className="developer-access-item" key={entry.email||i} style={{display:'flex',flexDirection:'column',alignItems:'stretch',gap:8,padding:'16px',border:'1px solid #e9d4d9',borderRadius:16,background:'#fff9f9',minWidth:0,overflowWrap:'anywhere'}}>
     <strong style={{display:'block',fontSize:15,lineHeight:1.35,color:'#741e35'}}>{entry.name||'Sem nome'}</strong>
     <span className="developer-access-email" style={{display:'block',fontSize:13,color:'#64565b',lineHeight:1.45,wordBreak:'break-word'}}>{entry.email}</span>
     <div style={{borderTop:'1px solid #eedee1',paddingTop:9,display:'flex',flexDirection:'column',gap:4}}>
      <span style={{fontSize:12,fontWeight:700,color:'#74535c'}}>Último acesso</span>
      <span style={{fontSize:13,color:'#4d4145'}}>{entry.last_seen_at?new Date(entry.last_seen_at).toLocaleString('pt-BR',{timeZone:'America/Sao_Paulo',dateStyle:'short',timeStyle:'short'}):'Nenhum acesso registrado'}</span>
      {entry.active_24h&&<span style={{color:'#256e4b',fontWeight:700,fontSize:12}}>Ativo nas últimas 24 horas</span>}
     </div>
    </article>)}
   </div>
  </div>
  <div className="card">
   <h3>Gestão de conteúdo</h3>
   <p className="muted">Gerencie comunicados, orientações e atualizações do aplicativo.</p>
   <div className="developer-content-grid" style={{display:'grid',gridTemplateColumns:'repeat(2,minmax(0,1fr))',gap:10,marginTop:16}}>
    {([['Atualizações','Atualizações'],['Notificações','Notificações'],['Como servir','Como servir'],['Como usar o site','Como usar o site']] as [string,string][]).map(([label,target])=>
     <button className="btn" type="button" key={target} onClick={()=>setView(target)} style={{display:'flex',alignItems:'center',justifyContent:'center',minWidth:0,width:'100%',minHeight:52,padding:'11px 7px',borderRadius:12,color:'#fff',background:'linear-gradient(130deg,#801b34,#a83450)',border:0,fontSize:13,fontWeight:700,lineHeight:1.3,textAlign:'center',whiteSpace:'normal'}}>{label}</button>
    )}
   </div>
  </div>
 </>}
 {view==='Atualizações'&&<><h2 className="title">Atualizações</h2>{developer&&<><div className="card"><h3>{updateId?'Editar atualização':'Publicar atualização'}</h3>{field('Versão (ex.: 1.1.0)',updateForm.version,v=>setUpdateForm({...updateForm,version:v}))}{field('Título',updateForm.title,v=>setUpdateForm({...updateForm,title:v}))}<label className="field">Novidades<textarea rows={5} value={updateForm.description} onChange={e=>setUpdateForm({...updateForm,description:e.target.value})}/></label><div className="btnrow">{b(updateId?'Salvar alterações':'Publicar',()=>{if(!updateForm.version.trim()||!updateForm.title.trim())return setError('Informe a versão e o título.');execute(()=>updateId?db!.from('site_updates').update(updateForm).eq('id',updateId):db!.from('site_updates').insert(updateForm)).then(ok=>{if(ok){setUpdateId('');setUpdateForm({version:'',title:'',description:''})}})})}{updateId&&b('Cancelar',()=>{setUpdateId('');setUpdateForm({version:'',title:'',description:''})},true)}</div></div></>}
<h3>Histórico de atualizações</h3>{updates.length===0&&<div className="card">Nenhuma atualização publicada ainda.</div>}{updates.map(u=><div className="card update-card" key={u.id}><div className="line"><h3>{u.title}</h3><span className="chip">v{u.version}</span></div><p style={{whiteSpace:'pre-wrap'}}>{u.description}</p><small className="muted">{new Date(u.published_at).toLocaleDateString('pt-BR')}</small>{developer&&<div className="btnrow" style={{marginTop:12}}>{b('Editar',()=>{setUpdateId(u.id);setUpdateForm({version:u.version,title:u.title,description:u.description})},true)}{b('Apagar',()=>{if(confirm('Apagar esta atualização definitivamente?'))execute(()=>db!.from('site_updates').delete().eq('id',u.id))},true)}</div>}</div>)}</>}
 {view==='Auditoria'&&developer&&<>
 <h2 className="title">Auditoria</h2>
 <p className="muted">Histórico das 250 alterações mais recentes, explicado em português. Apenas desenvolvedores podem consultar.</p>
 <div className="card"><div className="btnrow">{b('Atualizar registros',loadAudit)}<select aria-label="Filtrar auditoria" value={auditFilter} onChange={e=>setAuditFilter(e.target.value)}><option value="todos">Todos</option><option value="INSERT">Criações</option><option value="UPDATE">Alterações</option><option value="DELETE">Exclusões</option></select></div></div>
 {auditRows.filter(a=>auditFilter==='todos'||a.action===auditFilter).map(a=>{
  const info=summarizeAudit(a);
  return <article className="card audit-item audit-readable" key={a.id} style={{display:'flex',flexDirection:'column',alignItems:'stretch',gap:13,minWidth:0,overflow:'hidden',padding:18}}>
   <div style={{display:'block',minWidth:0,width:'100%'}}>
    <strong className="audit-readable-title" style={{display:'block',width:'100%',fontSize:16,lineHeight:1.45,overflowWrap:'anywhere'}}>{info.title}</strong>
   </div>
   <div style={{display:'block',width:'100%'}}>
    <span className="audit-readable-date" style={{display:'inline-block',borderRadius:10,padding:'7px 10px',background:'#f9ecee',color:'#81324a',fontSize:12,fontWeight:700}}>{new Date(a.happened_at).toLocaleString('pt-BR',{timeZone:'America/Sao_Paulo'})}</span>
   </div>
   <p className="muted audit-readable-actor" style={{display:'block',margin:0,overflowWrap:'anywhere'}}>Responsável: {a.actor_email||'Sistema / operação administrativa'}</p>
   <div className="audit-readable-details" style={{display:'flex',flexDirection:'column',gap:9,width:'100%',borderTop:'1px solid #f0e3e4',paddingTop:12}}>{info.details.map((detail,i)=><p key={i} style={{display:'block',margin:0,lineHeight:1.55,overflowWrap:'anywhere'}}>{detail}</p>)}</div>
  </article>
 })}
 {auditRows.length===0&&<div className="card">Toque em Atualizar registros para carregar a auditoria.</div>}
 </>}
 {view==='Usuários'&&developer&&<>
 <h2 className="title">Usuários</h2>
 <p className="muted">Gerencie coroinhas, pais, coordenadores e desenvolvedores. Alterações de acesso ficam registradas na auditoria.</p>
 <div className="card users-filter-card">
  <strong>{profiles.length} contas cadastradas</strong>
  <label className="field users-role-label">Selecionar usuários
   <select value={usersRole} onChange={e=>setUsersRole(e.target.value)}>
    <option value="coroinha">Coroinhas</option>
    <option value="pai">Pais e responsáveis</option>
    <option value="coordenadora">Coordenadores(as)</option>
    <option value="desenvolvedor">Desenvolvedores</option>
    <option value="pendentes">Aguardando aprovação</option>
   </select>
  </label>
 </div>
 {profiles.filter(p=>usersRole==='pendentes'?!p.approved:p.approved&&p.role===usersRole).length===0&&
  <div className="card users-empty">Nenhum {usersRole==='pendentes'?'cadastro pendente':'usuário aprovado nesta categoria'}.</div>}
 <div className="users-list">
 {profiles.filter(p=>usersRole==='pendentes'?!p.approved:p.approved&&p.role===usersRole).map(p=>
  <div className="item users-person-card" key={p.id}>
   <div className="users-person-identity" style={{display:'flex',flexDirection:'column',alignItems:'stretch',gap:6,minWidth:0,width:'100%'}}>
    <div className="users-person-name" style={{display:'block',fontWeight:800,fontSize:17,lineHeight:1.35,overflowWrap:'anywhere'}}>{p.name||'Sem nome'}</div>
    <div className="users-person-email" style={{display:'block',fontSize:13,lineHeight:1.5,overflowWrap:'anywhere',wordBreak:'break-word'}}>{p.email}</div>
    <div className="users-person-meta" style={{display:'block',fontSize:12,lineHeight:1.45,marginTop:2}}>{p.approved?'Aprovado':'Pendente'} {' • '}{p.role==='coroinha'?'Coroinha':p.role==='pai'?'Pai / Responsável':p.role==='coordenadora'?'Coordenador(a)':'Desenvolvedor'}</div>
   </div>
   <label className="field users-person-role">Tipo de usuário
    <select disabled={p.id===user.id||busy} value={p.role} onChange={e=>{const role=e.target.value;if(confirm('Alterar '+p.name+' para '+role+'?'))void execute(()=>db!.rpc('developer_manage_user',{p_user:p.id,p_action:'role',p_role:role}))}}>
     <option value="coroinha">Coroinha</option>
     <option value="pai">Pai / Responsável</option>
     <option value="coordenadora">Coordenador(a)</option>
     <option value="desenvolvedor">Desenvolvedor</option>
    </select>
   </label>
   {p.id!==user.id&&<div className="users-person-actions">
    {!p.approved&&b('Aprovar',()=>execute(()=>db!.from('profiles').update({approved:true}).eq('id',p.id)),true)}
    {b('Apagar conta',()=>{if(confirm('Excluir definitivamente a conta de '+p.email+'? Ela poderá se cadastrar novamente.'))void execute(()=>db!.rpc('developer_manage_user',{p_user:p.id,p_action:'delete'}))},true)}
    {b('Banir e-mail',()=>{if(confirm('Bloquear permanentemente o e-mail '+p.email+'? Ele não poderá entrar nem se cadastrar novamente.'))void execute(()=>db!.rpc('developer_manage_user',{p_user:p.id,p_action:'ban'}))},true)}
   </div>}
  </div>)}
 </div>
 </>}
 {view==='Coroinhas'&&coord&&<><h2 className="title">Coroinhas</h2><h3>Aguardando aprovação</h3>{profiles.filter(p=>!p.approved).map(p=><div className="item" key={p.id}><b>{p.name||p.email}</b><p className="muted">{p.role==='pai'?'Responsável':p.role} · {p.email}</p>{b('Aprovar acesso',()=>execute(()=>db!.from('profiles').update({approved:true}).eq('id',p.id)))}</div>)}<h3>Ativos</h3>{profiles.filter(p=>p.approved&&p.role==='coroinha').map(p=><div className="item" key={p.id}><b>{p.name}</b><p className="muted">{p.role} · {p.email}</p><span className="chip green">Confirmou: {assignments.filter(a=>a.server_id===p.id&&['confirmado','presente'].includes(a.status)).length}</span> <span className="chip">Desmarcou: {assignments.filter(a=>a.server_id===p.id&&a.status==='desmarcado').length}</span> <span className="chip red">Faltou: {assignments.filter(a=>a.server_id===p.id&&a.status==='faltou').length}</span>{field('Observação interna',p.notes||'',v=>setProfiles(profiles.map(x=>x.id===p.id?{...x,notes:v}:x)))}{b('Salvar observação',()=>execute(()=>db!.from('profiles').update({notes:p.notes}).eq('id',p.id)),true)}</div>)}</>}
 {view==='Notificações'&&<><h2 className="title">Notificações</h2>{coord&&<div className="card"><h3>{noticeEditor?'Editar mensagem':'Enviar nova notificação'}</h3>{developer&&!noticeEditor&&<label className="field">Formato<select value={screenKind} onChange={e=>{setScreenKind(e.target.value);setNoticeTitle('');setNoticeBody('')}}><option value="message">Mensagem normal (notificações)</option><option value="popup">Aviso na tela (pop-up)</option></select></label>}{field('Título',noticeTitle,setNoticeTitle)}<label className="field">Mensagem<textarea value={noticeBody} onChange={e=>setNoticeBody(e.target.value)}/></label>{!noticeEditor&&(screenKind==='popup'&&developer?<><label className="field">Quem verá o aviso<select value={screenRole} onChange={e=>{setScreenRole(e.target.value);setScreenTarget('')}}><option value="all">Todos os perfis aprovados</option><option value="coroinha">Coroinhas</option><option value="pai">Pais e responsáveis</option><option value="coordenadora">Coordenadores(as)</option><option value="desenvolvedor">Desenvolvedores</option><option value="individual">Uma pessoa específica</option></select></label>{screenRole==='individual'&&<label className="field">Usuário<select value={screenTarget} onChange={e=>setScreenTarget(e.target.value)}><option value="">Selecione um usuário</option>{profiles.filter(p=>p.approved).map(p=><option key={p.id} value={p.id}>{p.name||p.email}</option>)}</select></label>}<label className="field">Quando parar de mostrar<select value={screenRepeat} onChange={e=>setScreenRepeat(e.target.value)}><option value="optional">Permitir “Não mostrar novamente”</option><option value="once">Mostrar uma única vez por usuário</option><option value="always">Mostrar a cada nova entrada enquanto ativo</option></select></label><p className="muted">O aviso aparece ao entrar no sistema. Não é uma notificação push.</p></>:<label className="field">Destinatários<select value={noticeTarget} onChange={e=>setNoticeTarget(e.target.value)}><option value="coroinha">Todos os coroinhas aprovados</option><option value="pai">Pais e responsáveis aprovados</option><option value="coordenadora">Coordenadores aprovados</option><option value="todos">Todos os usuários aprovados</option><optgroup label="Enviar para uma pessoa">{profiles.filter(p=>p.approved).map(p=><option value={'user:'+p.id} key={p.id}>{p.name||p.email} · {p.role}</option>)}</optgroup></select></label>)}<div className="btnrow">{b(noticeEditor?'Salvar alterações':screenKind==='popup'&&developer?'Publicar aviso na tela':'Enviar mensagem',()=>{if(noticeEditor)editNotice();else if(screenKind==='popup'&&developer)sendScreenPopup();else sendNotice()})}{noticeEditor&&b('Cancelar',()=>{setNoticeEditor('');setNoticeTitle('');setNoticeBody('')},true)}</div></div>}{developer&&<div className="card"><h3>Avisos na tela publicados</h3>{screenSent.length===0&&<p className="muted">Nenhum aviso publicado.</p>}{screenSent.map(n=><div className="item" key={n.id}><b>{n.title}</b><p>{n.body}</p><small className="muted">{n.active?'Ativo':'Desativado'} · {n.target_role==='all'?'Todos os perfis':n.target_role==='individual'?profiles.find(p=>p.id===n.target_user_id)?.name||'Usuário específico':n.target_role} · {n.display_mode==='optional'?'Pode dispensar':n.display_mode==='once'?'Uma vez':'A cada entrada'}</small>{n.active&&<div className="btnrow">{b('Desativar aviso',()=>disableScreenPopup(n.id),true)}</div>}</div>)}</div>}{coord&&<div className="card"><h3>Avisos enviados</h3>{campaigns.map(n=><div className="item" key={n.group_id}><b>{n.title}</b><p>{n.body}</p><div className="btnrow">{b('Quem visualizou',()=>showNoticeReaders(n.group_id),true)}{b('Editar',()=>{setNoticeEditor(n.group_id);setNoticeTitle(n.title);setNoticeBody(n.body)},true)}{b('Apagar',()=>deleteNotice(n.group_id),true)}</div></div>)}{noticeRecipients.length>0&&<div className="card"><h3>Confirmações de leitura</h3>{noticeRecipients.map((n,i)=><div className="item" key={i}>{byId(n.user_id)} — {n.seen?'Visto em '+(n.read_at?fmt(n.read_at):'data não registrada'):'Não visto'}</div>)}</div>}</div>}{visibleNotices.map(n=><div className="item" key={n.id} onClick={()=>{}}><b>{n.title} {!n.seen?'•':''}</b><p>{n.body}</p><small className="muted">{fmt(n.created_at)} · {n.seen?'Visto':'Não visto'}</small>{!n.seen&&<div className="btnrow">{b('Marcar como visto',()=>execute(()=>db!.rpc('mark_notification_seen',{p_id:n.id})),true)}</div>}</div>)}{coord&&<><h3>Solicitações para servir/substituir</h3>{requests.filter(r=>r.status==='pendente').map(r=>{const mass=masses.find(m=>m.id===r.mass_id);const openSlots=assignments.filter(a=>a.mass_id===r.mass_id&&(r.type==='substituir'?a.id===r.assignment_id:(!a.server_id||a.status==='desmarcado')));const chosenSlot=requestFunctions[r.id]||'';const alreadyAssigned=assignments.some(a=>a.mass_id===r.mass_id&&a.server_id===r.user_id&&a.status!=='desmarcado');return <div className="item" key={r.id}><b>{byId(r.user_id)} — {r.type==='servir'?'Quer servir':'Solicitou substituição'}</b><p>{mass?mass.title+' · '+fmt(mass.starts_at):'Missa não encontrada'}</p><label className="field">Função para o coroinha<select value={openSlots.some(a=>a.id===chosenSlot)?chosenSlot:''} onChange={e=>setRequestFunctions(prev=>({...prev,[r.id]:e.target.value}))}><option value="">Selecione uma vaga disponível</option>{openSlots.map(a=><option key={a.id} value={a.id}>{a.function_name}</option>)}</select></label>{openSlots.length===0&&<p className="muted">Não há funções disponíveis nessa missa. Edite a missa para criar uma vaga antes de aprovar.</p>}{alreadyAssigned&&<p className="muted">Este coroinha já está escalado nessa missa.</p>}<div className="btnrow"><button className="btn" disabled={busy||!chosenSlot||!openSlots.some(a=>a.id===chosenSlot)||alreadyAssigned} onClick={async()=>{const ok=await execute(()=>db!.rpc('approve_service_request',{p_request_id:r.id,p_assignment_id:chosenSlot}));if(ok){setRequestFunctions(prev=>{const copy={...prev};delete copy[r.id];return copy});alert('Pedido aprovado! Função atribuída ao coroinha.')}}}>Aprovar na função</button>{b('Recusar',()=>execute(()=>db!.from('requests').update({status:'recusado'}).eq('id',r.id)),true)}</div></div>})}</>}</>}
 {view==='Relatórios'&&coord&&<><h2 className="title">Relatórios</h2><div className="grid2">{[['Missas',masses.length],['Coroinhas ativos',profiles.filter(p=>p.approved&&p.role==='coroinha').length],['Confirmações',assignments.filter(a=>a.status==='confirmado').length],['Faltas',assignments.filter(a=>a.status==='faltou').length],['Desmarcações',assignments.filter(a=>a.status==='desmarcado').length],['Vagas abertas',assignments.filter(a=>!a.server_id||a.status==='desmarcado').length]].map(([l,n])=><div className="metric" key={l}><b>{n}</b>{l}</div>)}</div><div style={{marginTop:22,marginBottom:14}}>{b('Baixar relatório mensal',()=>exportPdf('mes'))}</div></>}
 {view==='Downloads'&&coord&&<><h2 className="title">Downloads</h2><p>Selecione o período para gerar uma visualização pronta para imprimir ou salvar como PDF.</p><div className="card"><div className="btnrow">{b('Dia',()=>exportPdf('dia'))}{b('Semana',()=>exportPdf('semana'))}{b('Mês',()=>exportPdf('mes'))}</div></div></>}
 {view==='Como servir'&&<><h2 className="title">Como servir</h2>{coord&&<div className="card">{field('Função',guideForm.function_name,v=>setGuideForm({...guideForm,function_name:v}))}<label className="field">Como servir<textarea value={guideForm.instructions} onChange={e=>setGuideForm({...guideForm,instructions:e.target.value})}/></label><label className="field">Observações<textarea value={guideForm.notes} onChange={e=>setGuideForm({...guideForm,notes:e.target.value})}/></label>{b('Salvar orientação',()=>execute(()=>db!.from('guides').upsert(guideForm,{onConflict:'function_name'})))}</div>}{guides.filter(g=>!g.function_name.startsWith('__como_usar_')).map(g=><div className="card" key={g.id}><h3>{g.function_name}</h3><p style={{whiteSpace:'pre-wrap'}}>{g.instructions}</p><p className="muted">{g.notes}</p>{coord&&<div className="btnrow">{b('Editar',()=>setGuideForm({function_name:g.function_name,instructions:g.instructions,notes:g.notes||''}),true)}{b('Apagar',()=>{if(confirm('Excluir esta orientação?'))execute(()=>db!.from('guides').delete().eq('id',g.id))},true)}</div>}</div>)}</>}
 {view==='Escala automática'&&coord&&<><h2 className="title">Escala automática</h2><p>Cadastre os coroinhas fixos e depois aplique as regras às vagas abertas das missas cadastradas.</p><h3>Coroinhas fixos</h3><div className="card"><label className="field">Coroinha<select value={ruleForm.server_id} onChange={e=>setRuleForm({...ruleForm,server_id:e.target.value})}><option value="">Selecionar</option>{profiles.filter(p=>p.approved&&p.role==='coroinha').map(p=><option key={p.id} value={p.id}>{p.name}</option>)}</select></label><label className="field">Dia da semana<select value={ruleForm.weekday} onChange={e=>setRuleForm({...ruleForm,weekday:e.target.value})}>{['Domingo','Segunda','Terça','Quarta','Quinta','Sexta','Sábado'].map((x,i)=><option value={i} key={i}>{x}</option>)}</select></label><label className="field">Horário<input type="time" value={`${String(ruleForm.hour).padStart(2,'0')}:${String(ruleForm.minute).padStart(2,'0')}`} onChange={e=>{const [hour,minute]=e.target.value.split(':');if(hour!==undefined&&minute!==undefined)setRuleForm({...ruleForm,hour,minute})}}/></label>{field('Função',ruleForm.function_name,v=>setRuleForm({...ruleForm,function_name:v}))}{field('Igreja',ruleForm.location,v=>setRuleForm({...ruleForm,location:v}))}{b('Salvar coroinha fixo',()=>{if(!ruleForm.server_id||!ruleForm.function_name.trim()||!ruleForm.location.trim()){setError('Selecione um coroinha e informe função e igreja.');return}execute(()=>db!.from('fixed_rules').insert({...ruleForm,function_name:ruleForm.function_name.trim(),location:ruleForm.location.trim(),weekday:+ruleForm.weekday,hour:+ruleForm.hour,minute:+ruleForm.minute}))})}</div>{rules.map(r=><div className="item" key={r.id}>{byId(r.server_id)} • {r.function_name} • dia {r.weekday} às {String(r.hour).padStart(2,'0')}:{String(r.minute).padStart(2,'0')}{b('Excluir',()=>execute(()=>db!.from('fixed_rules').delete().eq('id',r.id)),true)}</div>)}
<div className="card"><h3>Aplicar escala automática</h3><p className="muted">Preenche as vagas abertas quando dia, horário completo, igreja e função coincidirem.</p>{b('Aplicar regras nas missas cadastradas',()=>{if(confirm('Aplicar regras de coroinhas fixos às vagas abertas?'))execute(async()=>{const changes=[];for(const m of masses){const d=new Date(m.starts_at);const localTime=d.toLocaleTimeString('en-GB',{timeZone:'America/Sao_Paulo',hour:'2-digit',minute:'2-digit',hour12:false});const [hour,minute]=localTime.split(':').map(Number);const weekday=new Date(day(m.starts_at)+'T12:00:00Z').getUTCDay();for(const r of rules.filter(r=>r.weekday===weekday&&Number(r.hour)===hour&&Number(r.minute)===minute&&(!r.location||r.location===m.location))){const slot=assignments.find(a=>a.mass_id===m.id&&a.function_name===r.function_name&&!a.server_id);if(slot)changes.push(db!.from('assignments').update({server_id:r.server_id}).eq('id',slot.id))}}const result=await Promise.all(changes);return {error:result.find(r=>r.error)?.error||null}})})}</div></>}
 {view==='Mensagens'&&coord&&!developer&&<><h2 className="title">Mensagens</h2><p className="muted">Sugestões, reclamações e dicas enviadas à coordenação.</p>{messages.length===0&&<div className="card">Nenhuma mensagem recebida.</div>}{messages.map(m=><div className="item" key={m.id}><b>{byId(m.user_id)} · {m.type==='sugestao'?'Sugestão':m.type==='reclamacao'?'Reclamação':'Dica'}</b><p style={{whiteSpace:'pre-wrap'}}>{m.body}</p><small className="muted">{m.created_at?fmt(m.created_at):''} · {m.seen?'Visto':'Não visto'}</small>{!m.seen&&<div className="btnrow" style={{marginTop:12}}>{b('Marcar como visto',()=>execute(()=>db!.rpc('mark_coordinator_message_seen',{p_id:m.id})),true)}</div>}</div>)}</>}
 {view==='Como usar o site'&&<><h2 className="title">Como usar o site</h2>{developer&&<div className="card"><h3>{helpEditTarget?'Editar instruções':'Publicar instruções'}</h3><label className="field">Destinatário<select value={helpTarget} disabled={!!helpEditTarget} onChange={e=>{setHelpTarget(e.target.value);setHelpText('')}}><option value="todos">Todos os perfis</option><option value="coroinha">Coroinhas</option><option value="pai">Pais e responsáveis</option><option value="coordenadora">Coordenadores(as)</option><option value="desenvolvedor">Desenvolvedores</option></select></label><label className="field">Como usar<textarea rows={7} value={helpText} placeholder="Escreva as instruções..." onChange={e=>setHelpText(e.target.value)}/></label><div className="btnrow">{b(helpEditTarget?'Salvar alterações':'Publicar',()=>{if(!helpText.trim())return setError('Escreva as instruções antes de publicar.');const current=guides.find(g=>g.id===helpEditTarget);const data={function_name:current?.function_name||'__como_usar_'+helpTarget+'_'+crypto.randomUUID(),instructions:helpText.trim(),notes:''};execute(()=>current?db!.from('guides').update({instructions:data.instructions}).eq('id',current.id):db!.from('guides').insert(data)).then(ok=>{if(ok){setHelpEditTarget('');setHelpText('')}})})}{helpEditTarget&&b('Cancelar',()=>{setHelpEditTarget('');setHelpText('')},true)}</div></div>}{developer?<><h3>Instruções publicadas</h3>{guides.filter(g=>g.function_name.startsWith('__como_usar_')).length===0&&<div className="card">Nenhuma instrução publicada.</div>}{guides.filter(g=>g.function_name.startsWith('__como_usar_')).map(g=>{const role=g.function_name.replace('__como_usar_','').split('_')[0];return <div className="card" key={g.id}><h3>{role==='todos'?'Todos os perfis':role==='pai'?'Pais e responsáveis':role==='coordenadora'?'Coordenadores(as)':role==='desenvolvedor'?'Desenvolvedores':'Coroinhas'}</h3><p style={{whiteSpace:'pre-wrap'}}>{g.instructions}</p><div className="btnrow">{b('Editar',()=>{setHelpEditTarget(g.id);setHelpTarget(role);setHelpText(g.instructions||'')},true)}{b('Apagar',()=>{if(confirm('Apagar esta orientação?'))execute(()=>db!.from('guides').delete().eq('id',g.id)).then(ok=>{if(ok&&helpEditTarget===g.id){setHelpEditTarget('');setHelpText('')}})},true)}</div></div>})}</>:<>{(()=>{const role=developer?'desenvolvedor':coord?'coordenadora':parent?'pai':'coroinha';const relevant=guides.filter(g=>g.function_name==='__como_usar_todos'||g.function_name.startsWith('__como_usar_todos_')||g.function_name==='__como_usar_'+role||g.function_name.startsWith('__como_usar_'+role+'_'));return relevant.length?relevant.map(g=><div className="card" style={{whiteSpace:'pre-wrap'}} key={g.id}><h3>{g.function_name.startsWith('__como_usar_todos')?'Orientações para todos':'Orientações do seu perfil'}</h3>{g.instructions}</div>):<div className="card">Nenhuma orientação publicada ainda.</div>})()}</>}</>}
 {view==='Suporte'&&<><h2 className="title">Suporte</h2><div className="card support-card"><h3>Com quem deseja falar?</h3><div className="btnrow">{b('Coordenador(a)',()=>setSupportTarget('coordenadora'),supportTarget!=='coordenadora')}{b('Desenvolvedor',()=>setSupportTarget('desenvolvedor'),supportTarget!=='desenvolvedor')}</div></div>{supportTarget==='coordenadora'&&<div className="card"><h3>Enviar mensagem à coordenação</h3><label className="field">Tipo de mensagem<select value={messageType} onChange={e=>setMessageType(e.target.value)}><option value="sugestao">Sugestão</option><option value="reclamacao">Reclamação</option><option value="dica">Dica</option></select></label><label className="field">Sua mensagem<textarea rows={5} value={messageBody} placeholder="Escreva o que deseja comunicar..." onChange={e=>setMessageBody(e.target.value)}/></label>{b('Enviar ao(à) coordenador(a)',()=>{if(!messageBody.trim())return setError('Escreva sua mensagem antes de enviar.');execute(()=>db!.from('messages').insert({user_id:user.id,type:messageType,body:messageBody.trim()})).then(ok=>{if(ok){setMessageBody('');alert('Mensagem enviada à coordenação!')}})})}</div>}{supportTarget==='desenvolvedor'&&<div className="card support-card"><h3>{developer?'Caixa de atendimentos':'Chat com o desenvolvedor'}</h3><p>{developer?'Veja os atendimentos abertos e as conversas arquivadas.':'Converse com o desenvolvedor e acompanhe seu atendimento pelo chat.'}</p><button type="button" className="btn full support-start-button" onClick={()=>setSupportChatOpen(true)}><MessageCircle size={19} aria-hidden="true"/><span>{developer?'Abrir atendimentos':'Iniciar chat de suporte'}</span></button></div>}</>}
 {view==='Ajustes'&&<><h2 className="title">Ajustes</h2>
 <div className="card notification-settings-card">
  <h3>Notificações no celular</h3>
  <p className="muted">Permita avisos mesmo com o aplicativo fechado. No iPhone, use o aplicativo adicionado à Tela de Início.</p>
  <button className={pushEnabled?'btn alt full':'btn full'} type="button" disabled={pushBusy} onClick={()=>pushEnabled?deactivatePush():activatePush()}>{pushBusy?'Aguarde…':pushEnabled?'Desativar notificações neste aparelho':'Ativar notificações neste aparelho'}</button>
  <p className="muted">O recebimento externo também depende da disponibilidade do serviço de notificações do aplicativo.</p>
 </div>
 <div className="card notification-settings-card">
  <h3>Quais avisos deseja receber?</h3>
  <p className="muted">Preferências individuais da sua conta. Marque ou desmarque os tipos desejados e salve.</p>
  <label className="pref-line notification-pref">
   <span>Receber notificações</span>
   <input type="checkbox" checked={notificationDraft.enabled!==false} onChange={e=>{setNotificationDraft(previous=>({...previous,enabled:e.target.checked}));setNotificationSaved(false)}}/>
  </label>
  {roleOptions.map(option=><label className={'pref-line notification-pref'+(option.future?' notification-pref-future':'')} key={option.key}>
   <span>{option.label}{option.future&&<small>Em desenvolvimento</small>}</span>
   <input type="checkbox" disabled={option.future||notificationDraft.enabled===false} checked={notificationDraft[option.key]!==false} onChange={e=>{setNotificationDraft(previous=>({...previous,[option.key]:e.target.checked}));setNotificationSaved(false)}}/>
  </label>)}
  <button type="button" className="btn full notification-save" disabled={busy} onClick={()=>void saveNotificationPreferences()}>{busy?'Salvando…':'Salvar alterações'}</button>
  {notificationSaved&&<p className="notification-save-confirm" role="status">Preferências salvas com sucesso.</p>}
 </div>
 </>}
 {view==='Perfil'&&<><h2 className="title">Meu perfil</h2><div className="card"><b>{profile.name}</b><p className="profile-role">{developer?'Desenvolvedor':coord?'Coordenador(a)':parent?'Pai/Responsável':'Coroinha'}</p><p>{profile.email}</p>{field('Nome',profileNameDraft??profile.name??'',setProfileNameDraft)}<button className="btn" disabled={busy} onClick={async()=>{const updatedName=(profileNameDraft??profile.name??'').trim();if(!updatedName){setError('Informe um nome antes de salvar.');return;}const saved=await execute(()=>db!.from('profiles').update({name:updatedName}).eq('id',user.id));if(saved)setProfileNameDraft(null)}}>Salvar nome</button></div></>}
 <footer className="site-credit"><span>Versão {updates[0]?.version||'1.0.0'}</span></footer></main><SupportChat db={db} userId={user.id} developer={developer} open={supportChatOpen} onOpenChange={setSupportChatOpen}/><nav className="bottom">{(coord?[[Home,'Início'],[CalendarDays,'Missas'],[Users,developer?'Usuários':'Coroinhas'],[ChartColumn,developer?'Painel':'Relatórios']]:parent?[[Home,'Início'],[CalendarDays,'Escalas mensais'],[Bell,'Notificações'],[UserCircle,'Perfil']]:[[Home,'Início'],[CalendarDays,'Escalas mensais'],[Plus,'Quero servir'],[Bell,'Notificações']]).map(([I,l]:any)=><button key={l} onClick={()=>{const target=l==='Painel'?'Painel desenvolvedor':l;setView(target);if(target==='Painel desenvolvedor'){void showDeveloper();void loadRecentAccess()}}}><I size={21}/>{l}</button>)}</nav>{drawer&&<div className="drawer-back" onClick={()=>setDrawer(false)}><aside className="drawer" onClick={e=>e.stopPropagation()}><h2>Olá, {profile.name}</h2><p className="drawer-role">{developer?'Desenvolvedor':coord?'Coordenador(a)':parent?'Pai/Responsável':'Coroinha'}</p>{menuItems.map(l=><button key={l} onClick={()=>{setView(l);setDrawer(false);if(l==='Painel desenvolvedor')showDeveloper();if(l==='Auditoria')loadAudit()}}>{l}</button>)}<button className="logout-danger" onClick={signout}><LogOut size={16}/> Sair</button></aside></div>}{pdfDocument&&createPortal(<div className="pdf-overlay" role="dialog" aria-modal="true" aria-label="Documento PDF"><section className="pdf-panel"><div className="pdf-panel-top"><button className="pdf-back" onClick={closePdf} aria-label="Voltar para o aplicativo">←</button><strong>Escala São Bento · PDF</strong></div><iframe className="pdf-preview" src={pdfDocument.url} title="Visualização do PDF"/><div className="pdf-actions"><button className="btn" onClick={sharePdf}>Salvar nos Arquivos</button><button className="btn alt" onClick={savePdfDownload}>Baixar PDF</button></div></section></div>,document.body)}{screenPopup&&<div className="screen-popup-overlay" role="presentation"><section className="screen-popup-card" role="alertdialog" aria-modal="true" aria-labelledby="screen-popup-title" aria-describedby="screen-popup-description"><div className="screen-popup-heading"><Bell size={23}/><h2 id="screen-popup-title">{screenPopup.title}</h2></div><p id="screen-popup-description">{screenPopup.body}</p>{screenPopup.display_mode==='optional'&&<label className="screen-popup-check"><input type="checkbox" checked={screenOptOut} onChange={e=>setScreenOptOut(e.target.checked)}/> Não mostrar novamente</label>}<button className="btn full" onClick={closeScreenPopup}>OK, entendi</button></section></div>}</div>;
}
