'use client';

import {useCallback,useEffect,useState} from 'react';
import {MessageCircle,X,Send,ArrowLeft,Archive,CheckCircle2,Inbox} from 'lucide-react';
import type {SupabaseClient} from '@supabase/supabase-js';

type Ticket={id:string;protocol:string;category:string;status:'aberto'|'encerrado';requester_name:string;requester_email:string;updated_at:string;created_at:string;closed_at:string|null;last_message:string;message_count:number};
type ChatMessage={id:string;body:string;sender_id:string;sender_name:string;developer:boolean;created_at:string};
type Props={db:SupabaseClient|null;userId:string;developer:boolean;open:boolean;onOpenChange:(next:boolean)=>void};
const dateText=(value:string)=>new Date(value).toLocaleString('pt-BR',{timeZone:'America/Sao_Paulo',day:'2-digit',month:'2-digit',hour:'2-digit',minute:'2-digit'});
const errorMessage=(err:unknown)=>{
 const text=typeof err==='object'&&err&&'message' in err?String((err as {message:unknown}).message):String(err||'');
 if(!text)return 'Não foi possível concluir a operação.';
 if(/not authenticated|not authorized|permission denied|não autorizado/i.test(text))return 'A sessão não permite esta operação. Entre novamente.';
 if(/failed to fetch|network|timeout|connection/i.test(text))return 'Sem conexão com o servidor. Tente novamente.';
 if(/support_|sqlstate|pgrst|invalid input/i.test(text))return 'Não foi possível atualizar o atendimento. Tente novamente.';
 return text;
};
export default function SupportChat({db,userId,developer,open,onOpenChange}:Props){
 const [tickets,setTickets]=useState<Ticket[]>([]);
 const [selected,setSelected]=useState<string|null>(null);
 const [archive,setArchive]=useState(false);
 const [chatMessages,setChatMessages]=useState<ChatMessage[]>([]);
 const [category,setCategory]=useState('Problema técnico');
 const [draft,setDraft]=useState('');
 const [initialMessage,setInitialMessage]=useState('');
 const [busy,setBusy]=useState(false);
 const [error,setError]=useState('');
 const [listLoaded,setListLoaded]=useState(false);
 const active=tickets.filter(t=>t.status==='aberto');
 const selectedTicket=tickets.find(t=>t.id===selected);
 const invoke=useCallback(async(name:string,args:Record<string,unknown>={})=>{
  if(!db)throw new Error('Serviço indisponível.');
  const result=await db.rpc(name as never,args as never);
  if(result.error)throw result.error;
  return result.data;
 },[db]);
 const loadTickets=useCallback(async()=>{
  if(!db)return;
  try{
   const data=await invoke('support_list');
   setTickets(Array.isArray(data)?data as Ticket[]:[]);
   setListLoaded(true);
  }catch(e){setError(errorMessage(e));setListLoaded(true)}
 },[db,invoke]);
 const loadMessages=useCallback(async(ticket:string)=>{
  if(!ticket)return;
  try{
   const data=await invoke('support_messages',{p_ticket:ticket});
   setChatMessages(Array.isArray(data)?data as ChatMessage[]:[]);
  }catch(e){setError(errorMessage(e))}
 },[invoke]);
 useEffect(()=>{
  if(!db||!userId)return;
  void loadTickets();
  const interval=setInterval(()=>void loadTickets(),12000);
  return()=>clearInterval(interval);
 },[db,userId,loadTickets]);
 useEffect(()=>{
  if(!open||!selected||!db)return;
  void loadMessages(selected);
  const interval=setInterval(()=>void loadMessages(selected),6000);
  return()=>clearInterval(interval);
 },[db,open,selected,loadMessages]);
 useEffect(()=>{
  if(selected&&!tickets.some(t=>t.id===selected))setSelected(null);
 },[selected,tickets]);
 const start=async()=>{
  if(!initialMessage.trim()){setError('Escreva sua mensagem antes de iniciar.');return}
  setBusy(true);setError('');
  try{
   const data=await invoke('support_create',{p_category:category,p_message:initialMessage.trim()}) as {id:string};
   setInitialMessage('');await loadTickets();setSelected(data.id);await loadMessages(data.id);
  }catch(e){setError(errorMessage(e))}finally{setBusy(false)}
 };
 const send=async()=>{
  if(!selected||!draft.trim())return;
  setBusy(true);setError('');
  try{
   await invoke('support_send',{p_ticket:selected,p_message:draft.trim()});
   setDraft('');await Promise.all([loadMessages(selected),loadTickets()]);
  }catch(e){setError(errorMessage(e))}finally{setBusy(false)}
 };
 const closeTicket=async()=>{
  if(!selected||!developer||!confirm('Encerrar este atendimento? As mensagens serão arquivadas no painel do desenvolvedor.'))return;
  setBusy(true);setError('');
  try{
   await invoke('support_close',{p_ticket:selected});
   await loadTickets();setSelected(null);setChatMessages([]);setArchive(true);
  }catch(e){setError(errorMessage(e))}finally{setBusy(false)}
 };
 const visibleTickets=tickets.filter(t=>developer?(archive?t.status==='encerrado':t.status==='aberto'):t.status==='aberto');
 const showBubble=active.length>0;
 return <>
  {showBubble&&!open&&<button type="button" className="support-floating" onClick={()=>onOpenChange(true)} aria-label={developer?'Abrir atendimentos de suporte':'Abrir conversa com suporte'}>
   <MessageCircle size={26} strokeWidth={2.2}/><span className="support-floating-count">{active.length}</span>
  </button>}
  {open&&<div className="support-chat-backdrop" role="presentation" onClick={()=>onOpenChange(false)}>
   <section className="support-chat-panel" role="dialog" aria-modal="true" aria-label="Atendimento por chat" onClick={e=>e.stopPropagation()}>
    <div className="support-chat-top">
     {selected&&<button type="button" className="support-chat-icon-button" aria-label="Voltar para atendimentos" onClick={()=>{setSelected(null);setError('')}}><ArrowLeft size={22}/></button>}
     <div className="support-chat-heading"><strong>{selectedTicket?selectedTicket.protocol:developer?'Suporte — atendimentos':'Chat de suporte'}</strong><span>{selectedTicket?selectedTicket.category:'Atendimento com protocolo'}</span></div>
     <button type="button" className="support-chat-icon-button" aria-label="Fechar janela do chat" onClick={()=>onOpenChange(false)}><X size={22}/></button>
    </div>
    {error&&<div className="support-chat-error" role="alert">{error}<button type="button" aria-label="Dispensar aviso" onClick={()=>setError('')}>×</button></div>}
    {selected&&selectedTicket?<>
     <div className="support-chat-messages">
      {chatMessages.map(m=><div className={'support-chat-message '+(m.sender_id===userId?'mine':'theirs')} key={m.id}>
       <small>{m.sender_id===userId?'Você':m.sender_name||'Suporte'} · {dateText(m.created_at)}</small>
       <p>{m.body}</p>
      </div>)}
      {!chatMessages.length&&<p className="support-chat-empty">Carregando mensagens…</p>}
     </div>
     {selectedTicket.status==='aberto'?<div className="support-chat-compose">
      <textarea aria-label="Sua mensagem" placeholder="Digite sua resposta…" value={draft} maxLength={2000} rows={2} onChange={e=>setDraft(e.target.value)}/>
      <button type="button" className="btn" disabled={busy||!draft.trim()} onClick={()=>void send()}><Send size={17}/> Enviar</button>
      {developer&&<button type="button" className="support-chat-end" disabled={busy} onClick={()=>void closeTicket()}>Encerrar e arquivar atendimento</button>}
     </div>:<div className="support-chat-closed"><CheckCircle2 size={17}/> Atendimento encerrado e arquivado.</div>}
    </>:<div className="support-chat-main">
     {developer&&<div className="support-chat-tabs">
      <button type="button" className={!archive?'selected':''} onClick={()=>setArchive(false)}><Inbox size={17}/> Abertos ({active.length})</button>
      <button type="button" className={archive?'selected':''} onClick={()=>setArchive(true)}><Archive size={17}/> Arquivados</button>
     </div>}
     {visibleTickets.length>0&&<div className="support-chat-list">{visibleTickets.map(t=><button type="button" key={t.id} className="support-chat-ticket" onClick={()=>{setSelected(t.id);setChatMessages([]);setError('')}}>
       <strong>{t.protocol}</strong><span>{developer?t.requester_name:t.category}</span>
       {developer&&<small>{t.requester_email}</small>}
       <p>{t.last_message||'Nenhuma mensagem'}</p>
       <small>Atualizado em {dateText(t.updated_at)}</small>
      </button>)}</div>}
     {!visibleTickets.length&&listLoaded&&<p className="support-chat-empty">{archive?'Nenhum atendimento arquivado.':developer?'Nenhum atendimento aberto.':'Nenhum atendimento em andamento.'}</p>}
     {!developer&&active.length===0&&<div className="support-chat-new">
      <h3>Iniciar atendimento</h3><p>Você receberá um número de protocolo. A conversa ficará disponível até o encerramento.</p>
      <label>Assunto<select value={category} onChange={e=>setCategory(e.target.value)}><option>Problema técnico</option><option>Dúvida</option><option>Sugestão</option><option>Outro</option></select></label>
      <label>Mensagem<textarea rows={4} maxLength={2000} placeholder="Explique como podemos ajudar…" value={initialMessage} onChange={e=>setInitialMessage(e.target.value)}/></label>
      <button type="button" className="btn full" disabled={busy||!initialMessage.trim()} onClick={()=>void start()}>{busy?'Enviando…':'Iniciar chat'}</button>
     </div>}
    </div>}
   </section>
  </div>}
 </>;
}
