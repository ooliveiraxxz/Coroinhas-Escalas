'use client';
import {useEffect,useState} from 'react';
import type {SupabaseClient} from '@supabase/supabase-js';
type Entry=Record<string,unknown>;
type Data={masses:Entry[];notifications:Entry[];polls:Entry[];announcements:Entry[];messages:Entry[];support:Entry[]};
type Group=keyof Data;
const groups:[Group,string][]=[['masses','Missas e escalas'],['notifications','Notificações'],['polls','Enquetes'],['announcements','Avisos pop-up'],['messages','Mensagens e sugestões'],['support','Atendimentos encerrados']];
const when=(value:unknown)=>value?new Date(String(value)).toLocaleString('pt-BR',{timeZone:'America/Sao_Paulo',day:'2-digit',month:'2-digit',year:'numeric',hour:'2-digit',minute:'2-digit'}):'—';
const title=(row:Entry,group:Group)=>{
 if(group==='masses')return String(row.title||'Celebração');
 if(group==='notifications'||group==='announcements')return String(row.title||'Aviso');
 if(group==='polls')return String(row.question||'Enquete');
 if(group==='support')return String(row.protocol||'Atendimento');
 return String(row.type||'Mensagem');
};
export default function Archives({db}:{db:SupabaseClient|null}){
 const [items,setItems]=useState<Data|null>(null);
 const [tab,setTab]=useState<Group>('masses');
 const [loading,setLoading]=useState(false);
 const [error,setError]=useState('');
 const load=async()=>{
  if(!db)return;
  setLoading(true);setError('');
  try{
   const res=await db.rpc('archive_list');
   if(res.error)throw res.error;
   const next=res.data as Partial<Data>||{};
   setItems({masses:next.masses||[],notifications:next.notifications||[],polls:next.polls||[],announcements:next.announcements||[],messages:next.messages||[],support:next.support||[]});
  }catch(e:unknown){setItems(null);setError(e instanceof Error?e.message:'Não foi possível consultar os arquivados.')}
  finally{setLoading(false)}
 };
 useEffect(()=>{void load()},[db]);
 return <div>
  <h2 className="title">Arquivados</h2>
  <p className="muted">Conteúdos removidos das telas normais. Eles são excluídos permanentemente 30 dias após o arquivamento. O acesso depende da permissão definida pelo Desenvolvedor.</p>
  <div className="card"><label className="field">Tipo de conteúdo
   <select value={tab} onChange={e=>setTab(e.target.value as Group)}>
    {groups.map(([key,label])=><option key={key} value={key}>{label}{items?` (${items[key].length})`:''}</option>)}
   </select>
  </label><button className="btn alt" onClick={()=>void load()} disabled={loading}>{loading?'Carregando…':'Atualizar lista'}</button></div>
  {error&&<div className="notice error">{error}</div>}
  {items&&items[tab].length===0&&<div className="card"><p className="muted">Nenhum conteúdo arquivado nesta categoria.</p></div>}
  {items?.[tab].map((entry,i)=><div className="card" key={String(entry.id||entry.protocol||i)}>
   <h3>{title(entry,tab)}</h3>
   <p className="muted">Arquivado em {when(entry.archived_at)} · Exclusão automática prevista para {when(entry.expires_at)}</p>
   {tab==='masses'&&<><p>{when(entry.starts_at)} · {String(entry.location||'')}</p>
    {(Array.isArray(entry.assignments)?entry.assignments:[]).map((a:Entry,j:number)=><div className="item" key={j}><b>{String(a.function_name||'Função')}</b><p className="muted">{String(a.server||'Vaga disponível')} · {String(a.service_group||'')} · {String(a.status||'')}</p></div>)}
   </>}
   {(tab==='notifications'||tab==='announcements')&&<p style={{whiteSpace:'pre-wrap'}}>{String(entry.body||'')}</p>}
   {tab==='polls'&&<p>{String(entry.votes||0)} voto(s) · Encerrada em {when(entry.ends_at)}</p>}
   {tab==='messages'&&<><p>{String(entry.body||'')}</p><p className="muted">Enviado por {String(entry.author||'Usuário')}</p></>}
   {tab==='support'&&<><p>{String(entry.category||'')} · Encerrado em {when(entry.closed_at)}</p>
    {(Array.isArray(entry.messages)?entry.messages:[]).map((a:Entry,j:number)=><div className="item" key={j}><b>{String(a.author||'Usuário')}</b><p>{String(a.body||'')}</p><small className="muted">{when(a.created_at)}</small></div>)}
   </>}
  </div>)}
 </div>;
}
