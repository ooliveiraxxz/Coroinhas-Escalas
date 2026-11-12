'use client';
import {useCallback,useEffect,useState} from 'react';
import type {SupabaseClient} from '@supabase/supabase-js';
type Question={id:string;question:string;ends_at:string;created_at:string;target_role:string;created_by:string;creator_name:string;answer:string|null;answer_count:number|null};
type Response={name:string;answer:string;created_at:string};
type Props={db:SupabaseClient|null;canPublish:boolean;isDeveloper:boolean;group:string;showComposer:boolean};
const dateLabel=(v:string)=>new Date(v).toLocaleString('pt-BR',{timeZone:'America/Sao_Paulo',dateStyle:'short',timeStyle:'short'});
export default function OpenQuestions({db,canPublish,isDeveloper,group,showComposer}:Props){
 const [items,setItems]=useState<Question[]>([]);
 const [question,setQuestion]=useState('');
 const [target,setTarget]=useState(group);
 const [expires,setExpires]=useState('');
 const [drafts,setDrafts]=useState<Record<string,string>>({});
 const [selected,setSelected]=useState('');
 const [answers,setAnswers]=useState<Response[]>([]);
 const [busy,setBusy]=useState(false);
 const [error,setError]=useState('');
 const [success,setSuccess]=useState('');
 const reload=useCallback(async()=>{if(!db)return;const r=await db.rpc('open_question_list');if(!r.error&&Array.isArray(r.data))setItems(r.data as Question[]);else if(r.error)setError(r.error.message||'Falha ao carregar perguntas.')},[db]);
 useEffect(()=>{void reload()},[reload]);
 useEffect(()=>{if(!db)return;const timer=setInterval(()=>void reload(),30000);return()=>clearInterval(timer)},[db,reload]);
 const publish=async()=>{
  if(!db||busy)return;
  if(!question.trim()||!expires){setError('Informe a pergunta e a data de encerramento.');return;}
  setBusy(true);setError('');setSuccess('');
  try{const r=await db.rpc('open_question_create',{p_question:question.trim(),p_target:isDeveloper?target:group,p_ends_at:new Date(expires).toISOString()});if(r.error)throw r.error;setQuestion('');setExpires('');setSuccess('Pergunta publicada. Os participantes receberão uma notificação.');await reload()}
  catch(e:any){setError(e?.message||'Não foi possível publicar.')}finally{setBusy(false)}
 };
 const send=async(id:string)=>{
  const value=(drafts[id]||'').trim();if(!db||busy||!value)return;
  setBusy(true);setError('');setSuccess('');
  try{const r=await db.rpc('open_question_answer',{p_question:id,p_answer:value});if(r.error)throw r.error;setDrafts(v=>({...v,[id]:''}));setSuccess('Sua resposta foi enviada.');await reload()}
  catch(e:any){setError(e?.message||'Não foi possível enviar.')}finally{setBusy(false)}
 };
 const read=async(id:string)=>{
  if(!db||busy)return;setBusy(true);setError('');
  try{const r=await db.rpc('open_question_responses',{p_question:id});if(r.error)throw r.error;setAnswers(Array.isArray(r.data)?r.data as Response[]:[]);setSelected(id)}
  catch(e:any){setError(e?.message||'Não foi possível consultar respostas.')}finally{setBusy(false)}
 };
 return <div className="open-questions">
  {showComposer&&canPublish&&<div className="card"><h3>Caixinha de perguntas</h3><p className="muted">Como nos Stories: publique uma pergunta e receba respostas escritas individualmente.</p>
   <label className="field">Pergunta<textarea rows={3} maxLength={500} placeholder="Ex.: O que podemos melhorar nas escalas?" value={question} onChange={e=>setQuestion(e.target.value)}/></label>
   {isDeveloper&&<label className="field">Público<select value={target} onChange={e=>setTarget(e.target.value)}><option value="todos">Todos os perfis</option><option value="coroinha">Coroinhas</option><option value="cerimoniario">Cerimoniários</option><option value="pai">Pais e responsáveis</option><option value="coordenadora">Coordenadores</option></select></label>}
   <label className="field">Receber respostas até<input type="datetime-local" value={expires} onChange={e=>setExpires(e.target.value)}/></label>
   <button className="btn full" type="button" disabled={busy||question.trim().length<5||!expires} onClick={()=>void publish()}>{busy?'Publicando…':'Enviar pergunta'}</button>
  </div>}
  {error&&<div className="notice error" role="alert">{error}</div>}{success&&<p className="muted" role="status">{success}</p>}
  {items.map(q=><div className="card open-question-card" key={q.id}>
   <small className="muted">Pergunta de {q.creator_name} · até {dateLabel(q.ends_at)}</small><h3>{q.question}</h3>
   {q.answer?<p className="open-question-answer">Sua resposta: {q.answer}</p>:new Date(q.ends_at)>new Date()&&<><textarea rows={3} maxLength={2000} placeholder="Escreva sua resposta…" aria-label={'Responder: '+q.question} value={drafts[q.id]||''} onChange={e=>setDrafts(prev=>({...prev,[q.id]:e.target.value}))}/><button type="button" className="btn" disabled={busy||!(drafts[q.id]||'').trim()} onClick={()=>void send(q.id)}>Enviar resposta</button></>}
   {canPublish&&(q.created_by||isDeveloper)&&q.answer_count!==null&&<button type="button" className="btn alt" disabled={busy} onClick={()=>void read(q.id)}>Ver respostas ({q.answer_count})</button>}
  </div>)}
  {selected&&<div className="card"><div className="line"><h3>Respostas recebidas</h3><button type="button" className="btn alt" onClick={()=>setSelected('')}>Fechar</button></div>{answers.length===0?<p className="muted">Ainda não há respostas.</p>:answers.map((a,i)=><div className="item" key={i}><strong>{a.name}</strong><p>{a.answer}</p><small className="muted">{dateLabel(a.created_at)}</small></div>)}</div>}
  {items.length===0&&<p className="muted">Nenhuma pergunta disponível no momento.</p>}
 </div>;
}
