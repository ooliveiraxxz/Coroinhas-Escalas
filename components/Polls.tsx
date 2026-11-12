'use client';
import {useCallback,useEffect,useState} from 'react';
import {BarChart3,Clock,CheckCircle2,Plus,Trash2} from 'lucide-react';
import type {SupabaseClient} from '@supabase/supabase-js';

type Option={id:string;label:string;position:number};
type Result={id:string;label:string;votes:number;voters:{name:string;voted_at:string}[]};
type Poll={id:string;created_by:string;question:string;starts_at:string;ends_at:string;multiple_answers:boolean;priority:boolean;state:'agendada'|'aberta'|'encerrada';voted:boolean;my_options:string[];options:Option[];results:Result[];respondents:number};
type Props={db:SupabaseClient|null;coordinator:boolean;userRole:string;userId:string;isDeveloper:boolean;};
const dateTime=(v:string)=>new Date(v).toLocaleString('pt-BR',{timeZone:'America/Sao_Paulo',dateStyle:'short',timeStyle:'short'});
const toDatetimeLocal=(v:string)=>{
 const d=new Date(v);d.setMinutes(d.getMinutes()-d.getTimezoneOffset());return d.toISOString().slice(0,16);
};
function localNow(){
 const d=new Date();d.setMinutes(d.getMinutes()-d.getTimezoneOffset());return d.toISOString().slice(0,16);
}
export default function Polls({db,coordinator,userRole,userId,isDeveloper}:Props){
 const [polls,setPolls]=useState<Poll[]>([]),[loading,setLoading]=useState(false),[saving,setSaving]=useState(false),[message,setMessage]=useState('');
 const [question,setQuestion]=useState(''),[options,setOptions]=useState(['','']),[start,setStart]=useState(localNow),[end,setEnd]=useState(''),[multiple,setMultiple]=useState(false),[priority,setPriority]=useState(false);
 const [choices,setChoices]=useState<Record<string,string[]>>({});
 const [editingVote,setEditingVote]=useState<string|null>(null);
 const [editingId,setEditingId]=useState<string|null>(null);
 const [optionIds,setOptionIds]=useState<(string|null)[]>([null,null]);
 const resetForm=()=>{
  setEditingId(null);setQuestion('');setOptions(['','']);setOptionIds([null,null]);
  setMultiple(false);setPriority(false);setStart(localNow());setEnd('');
 };
 const editPoll=(poll:Poll)=>{
  setMessage('');setEditingId(poll.id);setQuestion(poll.question);
  setOptions(poll.options.map(o=>o.label));setOptionIds(poll.options.map(o=>o.id));
  setStart(toDatetimeLocal(poll.starts_at));setEnd(toDatetimeLocal(poll.ends_at));
  setMultiple(poll.multiple_answers);setPriority(poll.priority);
 };
 const rpc=useCallback(async(name:string,params:Record<string,unknown>={})=>{
  if(!db)throw Error('Sem conexão com o servidor.');
  const {data,error}=await db.rpc(name as never,params as never);
  if(error)throw error;
  return data;
 },[db]);
 const load=useCallback(async()=>{
  if(!db)return;
  try{
   const data=await rpc('poll_list');setPolls(Array.isArray(data)?data as Poll[]:[]);
  }catch{setMessage('Não foi possível consultar as enquetes. Atualize a página.')}
 },[db,rpc]);
 useEffect(()=>{if(!db)return;void load();const timer=setInterval(()=>void load(),20000);return()=>clearInterval(timer)},[db,load]);
 const create=async()=>{
  if(!question.trim()||options.some(o=>!o.trim())||options.length<2){setMessage('Informe a pergunta e ao menos duas opções.');return;}
  if(!start||!end||new Date(end)<=new Date(start)||(!editingId&&new Date(end)<=new Date())){setMessage('Confira as datas de início e encerramento.');return;}
  setSaving(true);setMessage('');
  try{
   if(editingId){
    await rpc('poll_update',{p_poll:editingId,p_question:question.trim(),
     p_options:JSON.stringify(options.map((label,i)=>({id:optionIds[i],label:label.trim()}))),
     p_starts_at:new Date(start).toISOString(),p_ends_at:new Date(end).toISOString(),
     p_multiple:multiple,p_priority:priority});
    setMessage('Enquete atualizada. Os votos já registrados foram preservados.');
   }else{
    await rpc('poll_create',{p_question:question.trim(),p_options:JSON.stringify(options.map(o=>o.trim())),p_starts_at:new Date(start).toISOString(),p_ends_at:new Date(end).toISOString(),p_multiple:multiple,p_priority:priority});
    setMessage('Enquete criada! A abertura e os avisos serão realizados no horário programado.');
   }
   resetForm();await load();
  }catch(e:any){setMessage(e?.message&&/^[^A-Za-z]*[A-Za-zÀ-ú ]{5,100}$/.test(e.message)?e.message:'Não foi possível criar a enquete. Confira os campos.')}
  finally{setSaving(false)}
 };
 const vote=async(poll:Poll)=>{
  const picked=choices[poll.id]||[];
  if(!picked.length){setMessage('Selecione uma opção para responder.');return;}
  setSaving(true);setMessage('');
  try{
   await rpc(editingVote===poll.id?'poll_change_vote':'poll_vote',{p_poll:poll.id,p_options:picked});
   setChoices(old=>({...old,[poll.id]:[]}));
   setMessage(editingVote===poll.id?'Sua resposta foi atualizada com sucesso.':'Sua resposta foi registrada.');
   setEditingVote(null);
   await load();
  }
  catch(e:any){setMessage(e?.message||'Não foi possível registrar a resposta.')}
  finally{setSaving(false)}
 };
 const manage=async(poll:Poll,action:'close'|'archive')=>{
  if(saving||!coordinator)return;
  if(!confirm(action==='close'?'Encerrar esta enquete agora? Os votos já recebidos serão preservados.':'Apagar esta enquete da lista? Ela ficará arquivada até a exclusão automática.'))return;
  setSaving(true);setMessage('');
  try{
   const result=await rpc(action==='close'?'poll_close':'poll_archive',{p_poll:poll.id});
   if(result!==true)throw Error('Esta enquete não está disponível para a ação.');
   if(editingId===poll.id)resetForm();
   setMessage(action==='close'?'Enquete encerrada.':'Enquete arquivada.');
   await load();
  }catch(e:any){setMessage(e?.message||'Não foi possível concluir a operação.')}
  finally{setSaving(false)}
 };
 const display=coordinator?polls:userRole==='coroinha'?polls:[];
 return <div className="polls-root">
  {coordinator&&<section className="card poll-create">
   <h3><BarChart3 size={20}/> {editingId?'Editar enquete':'Criar enquete'}</h3>
   {editingId&&<p className="muted">Opções que já receberam votos não podem ser renomeadas ou excluídas. As respostas existentes serão preservadas.</p>}
   <label className="field">Pergunta<input maxLength={250} value={question} onChange={e=>setQuestion(e.target.value)} placeholder="Qual sua pergunta?"/></label>
   <div className="poll-options"><strong>Opções de resposta</strong>{options.map((o,i)=><div className="poll-option-editor" key={i}>
     <input aria-label={'Opção '+(i+1)} maxLength={140} value={o} onChange={e=>setOptions(old=>old.map((v,j)=>j===i?e.target.value:v))} placeholder={'Opção '+(i+1)}/>
     {options.length>2&&<button type="button" aria-label={'Remover opção '+(i+1)} onClick={()=>{setOptions(old=>old.filter((_,j)=>j!==i));setOptionIds(old=>old.filter((_,j)=>j!==i))}}><Trash2 size={18}/></button>}
    </div>)}
    {options.length<10&&<button type="button" className="btn alt full" onClick={()=>{setOptions(old=>[...old,'']);setOptionIds(old=>[...old,null])}}><Plus size={16}/> Adicionar opção</button>}
   </div>
   <label className="field poll-datetime">Início<input type="datetime-local" value={start} onChange={e=>setStart(e.target.value)}/></label>
   <label className="field poll-datetime">Encerramento<input type="datetime-local" value={end} onChange={e=>setEnd(e.target.value)}/></label>
   <label className="poll-check"><span>Permitir várias respostas</span><input type="checkbox" checked={multiple} onChange={e=>setMultiple(e.target.checked)}/></label>
   <label className="poll-check"><span>Priorizar notificação</span><input type="checkbox" checked={priority} onChange={e=>setPriority(e.target.checked)}/></label>
   <button type="button" className="btn full" disabled={saving} onClick={()=>void create()}>{saving?'Salvando…':editingId?'Salvar alterações':'Criar enquete'}</button>
   {editingId&&<button type="button" className="btn alt full" disabled={saving} onClick={()=>{resetForm();setMessage('Edição cancelada.')}}>Cancelar edição</button>}
  </section>}
  {message&&<div className="poll-status" role="status">{message}</div>}
  {(display.length>0||coordinator)&&<h3 className="poll-list-heading">{coordinator?'Enquetes e resultados':'Enquetes'}</h3>}
  {display.map(p=><section className="card poll-card" key={p.id}>
   <div className="poll-heading"><strong>{p.question}</strong><span>{p.state==='aberta'?'Aberta':p.state==='agendada'?'Agendada':'Encerrada'}</span></div>
   {coordinator&&(p.created_by===userId||isDeveloper)&&<div className="btnrow">
    {p.state!=='encerrada'&&<button type="button" className="poll-edit-button" disabled={saving} onClick={()=>{editPoll(p);window.scrollTo({top:0,behavior:'smooth'})}}>Editar enquete</button>}
    {p.state!=='encerrada'&&<button type="button" className="btn alt" disabled={saving} onClick={()=>void manage(p,'close')}>Encerrar</button>}
    {p.state==='encerrada'&&<button type="button" className="btn danger" disabled={saving} onClick={()=>void manage(p,'archive')}><Trash2 size={17}/> Apagar</button>}
   </div>}
   {p.state==='encerrada'&&!coordinator?<p className="poll-closed"><CheckCircle2 size={17}/> Enquete encerrada. A votação não está mais disponível.</p>:<>
    <p className="muted poll-dates"><Clock size={14}/> {dateTime(p.starts_at)} até {dateTime(p.ends_at)}</p>
    {coordinator?<div className="poll-results">
     <p className="muted">{p.respondents||0} pessoa(s) responderam</p>
     {p.results.map(o=><div key={o.id} className="poll-result-group">
      <div className="poll-result"><span>{o.label}</span><strong>{o.votes} voto(s)</strong></div>
      {(o.voters?.length||0)>0?<ul className="poll-voter-list" aria-label={'Coroinhas que escolheram '+o.label}>
       {o.voters.map((v,i)=><li key={i}>{v.name}</li>)}
      </ul>:<p className="poll-voter-empty">Nenhum coroinha selecionou esta opção.</p>}
     </div>)}
    </div>:p.voted&&editingVote!==p.id?<>
      <p className="poll-voted"><CheckCircle2 size={17}/> Sua resposta foi registrada.</p>
      {p.state==='aberta'&&<button type="button" className="btn alt full" disabled={saving} onClick={()=>{
       setChoices(prev=>({...prev,[p.id]:Array.isArray(p.my_options)?p.my_options:[]}));
       setEditingVote(p.id);setMessage('');
      }}>Alterar minha resposta</button>}
     </>:p.state==='aberta'?<>
      {p.options.map(o=><label className="poll-vote-option" key={o.id}>
       <input type={p.multiple_answers?'checkbox':'radio'} name={'poll-'+p.id} checked={(choices[p.id]||[]).includes(o.id)} onChange={e=>setChoices(old=>({...old,[p.id]:p.multiple_answers?(e.target.checked?[...(old[p.id]||[]),o.id]:(old[p.id]||[]).filter(x=>x!==o.id)):[o.id]}))}/>
       <span>{o.label}</span>
      </label>)}
      <button type="button" className="btn full" disabled={saving||!(choices[p.id]||[]).length} onClick={()=>void vote(p)}>{editingVote===p.id?'Salvar nova resposta':'Enviar resposta'}</button>
      {editingVote===p.id&&<button type="button" className="btn alt full" disabled={saving} onClick={()=>{setEditingVote(null);setChoices(prev=>({...prev,[p.id]:[]}))}}>Cancelar alteração</button>}
     </>:null}
   </>}
  </section>)}
  {!coordinator&&display.length===0&&userRole==='coroinha'&&<p className="card muted">Nenhuma enquete disponível no momento.</p>}
 </div>;
}
