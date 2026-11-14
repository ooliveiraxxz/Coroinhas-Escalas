'use client';
import {useEffect,useMemo,useState} from 'react';
import type {SupabaseClient} from '@supabase/supabase-js';
type Row=Record<string,any>;
type Props={db:SupabaseClient|null;users:Row[]};
type Section='automacoes'|'gerenciamento'|'temporarias';
const groupOrder=['Coroinhas e cerimoniários','Pais e responsáveis','Coordenação','Desenvolvedor'];
const localDate=(v:string)=>new Date(v).toLocaleString('pt-BR',{timeZone:'America/Sao_Paulo'});
function Toggle({enabled,onChange,label}:{enabled:boolean;onChange:(v:boolean)=>void;label:string}){
 return <button type="button" role="switch" aria-label={label} aria-checked={enabled} onClick={()=>onChange(!enabled)}
 style={{width:54,height:31,border:0,flexShrink:0,borderRadius:22,padding:3,cursor:'pointer',background:enabled?'#268358':'#aaa',display:'flex',alignItems:'center',justifyContent:enabled?'flex-end':'flex-start'}}>
 <span style={{width:25,height:25,background:'#fff',borderRadius:'50%',boxShadow:'0 1px 4px #4445'}}/>
 </button>;
}
export default function PermissionCenter({db,users}:Props){
 const [section,setSection]=useState<Section>('automacoes');
 const [userId,setUserId]=useState('');
 const [autoRows,setAutoRows]=useState<Row[]>([]);
 const [permRows,setPermRows]=useState<Row[]>([]);
 const [storedRules,setStoredRules]=useState<Row[]>([]);
 const [changes,setChanges]=useState<Record<string,boolean>>({});
 const [selectedRevokes,setSelectedRevokes]=useState<Record<string,boolean>>({});
 const [confirmName,setConfirmName]=useState('');
 const [expires,setExpires]=useState('');
 const [working,setWorking]=useState(false);
 const [error,setError]=useState('');
 const [success,setSuccess]=useState('');
 const [expanded,setExpanded]=useState('Coroinhas e cerimoniários');
 const eligible=users.sort((a,b)=>String(a.name||'').localeCompare(String(b.name||''),'pt-BR'));
 useEffect(()=>{if(!eligible.some(u=>u.id===userId))setUserId(eligible[0]?.id||'')},[users,userId]);
 const fetchAll=async()=>{
  if(!db)return;
  setWorking(true);setError('');
  try{
   const jobs=await Promise.all([db.rpc('developer_automation_snapshot'),db.rpc('developer_list_permission_rules')]);
   if(jobs[0].error)throw jobs[0].error;
   if(jobs[1].error)throw jobs[1].error;
   setAutoRows(Array.isArray(jobs[0].data)?jobs[0].data:[]);
   setStoredRules(Array.isArray(jobs[1].data)?jobs[1].data:[]);
  }catch(e:any){setError(e?.message||'Não foi possível carregar as configurações.')}
  finally{setWorking(false)}
 };
 useEffect(()=>{void fetchAll()},[db]);
 useEffect(()=>{let active=true;setChanges({});setSelectedRevokes({});setError('');setConfirmName('');
  if(!db||!userId){setPermRows([]);return;}
  db.rpc('developer_permission_snapshot',{p_user:userId}).then(({data,error})=>{
   if(!active)return;
   if(error)setError(error.message);
   else setPermRows(Array.isArray(data)?data:[]);
  });return()=>{active=false};
 },[db,userId]);
 const activeRows=section==='automacoes'?autoRows:permRows;
 const toggle=(key:string,base:boolean)=>setChanges(prev=>({...prev,[key]:!(Object.hasOwn(prev,key)?prev[key]:base)}));
 const hasChanges=Object.keys(changes).length>0;
 const getState=(key:string,base:boolean)=>Object.hasOwn(changes,key)?changes[key]:base;
 const current=useMemo(()=>eligible.find(u=>u.id===userId),[eligible,userId]);
 const save=async()=>{
  if(!db||working||!hasChanges)return;
  if(confirmName!=='DESENVOLVEDOR'){setError('Digite DESENVOLVEDOR antes de salvar.');return;}
  if(section==='temporarias'&&(!expires||!Number.isFinite(new Date(expires).getTime())||new Date(expires)<=new Date())){setError('Informe uma data e hora de expiração futuras.');return;}
  setWorking(true);setError('');setSuccess('');
  try{
   const updates=Object.entries(changes).map(([key,state])=>section==='automacoes'?{key,enabled:state}:{key,allowed:state});
   const result=section==='automacoes'
    ?await db.rpc('developer_apply_automations',{p_changes:updates,p_confirmation:confirmName})
    :await db.rpc('developer_apply_permissions',{p_user:userId,p_changes:updates,p_until:section==='temporarias'?new Date(expires).toISOString():null,p_confirmation:confirmName});
   if(result.error)throw result.error;
   setChanges({});setConfirmName('');setExpires('');setSuccess('Alterações salvas e aplicadas no servidor.');
   await fetchAll();
   if(section!=='automacoes'){
    const snapshot=await db.rpc('developer_permission_snapshot',{p_user:userId});
    if(!snapshot.error)setPermRows(Array.isArray(snapshot.data)?snapshot.data:[]);
   }
  }catch(e:any){setError(e?.message||'Não foi possível salvar.')}
  finally{setWorking(false)}
 };
 const revokeBulk=async()=>{
  const ids=validRules.filter(rule=>selectedRevokes[rule.id]).map(rule=>String(rule.id));
  if(!db||working||ids.length===0)return;
  if(confirmName!=='DESENVOLVEDOR'){setError('Digite DESENVOLVEDOR para revogar as permissões.');return;}
  if(!confirm('Revogar '+ids.length+' permissões temporárias selecionadas agora?'))return;
  setWorking(true);setError('');setSuccess('');
  try{
   const result=await db.rpc('developer_revoke_permissions_bulk',{p_user:userId,p_ids:ids,p_confirmation:confirmName});
   if(result.error)throw result.error;
   setSelectedRevokes({});setConfirmName('');
   setSuccess(String(result.data||ids.length)+' permissões temporárias revogadas em uma única operação.');
   const jobs=await Promise.all([db.rpc('developer_list_permission_rules'),db.rpc('developer_permission_snapshot',{p_user:userId})]);
   if(jobs[0].error)throw jobs[0].error;
   setStoredRules(Array.isArray(jobs[0].data)?jobs[0].data:[]);
   if(!jobs[1].error)setPermRows(Array.isArray(jobs[1].data)?jobs[1].data:[]);
  }catch(e:any){setError(e?.message||'Não foi possível revogar as permissões.')}
  finally{setWorking(false)}
 };
 const validRules=storedRules.filter(r=>r.subject_user===userId&&r.expires_at&&new Date(r.expires_at)>new Date());
 return <div>
  <h2 className="title">Permissões</h2>
  <p className="muted">Controle por pessoa, com chaves liga/desliga. Nada muda até você confirmar e salvar.</p>
  <div className="card"><label className="field">Selecionar seção<select value={section} onChange={e=>{setSection(e.target.value as Section);setChanges({});setSelectedRevokes({});setConfirmName('');setSuccess('')}}><option value="automacoes">Automações</option><option value="gerenciamento">Gerenciamento</option><option value="temporarias">Permissões temporárias</option></select></label></div>
  {section!=='automacoes'&&<div className="card"><label className="field">Selecionar pessoa<select value={userId} onChange={e=>setUserId(e.target.value)}>{eligible.map(u=><option key={u.id} value={u.id}>{u.name||u.email} — {u.role}{u.approved?'':' (aguardando aprovação)'}</option>)}</select></label><p className="muted">As opções habilitadas indicam o que {current?.name||'esta pessoa'} pode fazer. Alterações individuais têm prioridade sobre o perfil padrão.</p></div>}
  {section==='automacoes'?<div className="card"><h3>Automações identificadas no sistema</h3>{autoRows.map(row=><div className="item" key={row.key} style={{display:'flex',alignItems:'center',justifyContent:'space-between',gap:12}}><div style={{flex:1,minWidth:0}}><strong>{row.label}</strong><p className="muted" style={{margin:'4px 0'}}>{row.description}</p></div><Toggle enabled={getState(row.key,Boolean(row.enabled))} onChange={()=>toggle(row.key,Boolean(row.enabled))} label={row.label}/></div>)}</div>
  :<>
  {section==='temporarias'&&<div className="card"><label className="field">Acesso permitido até<input className="permission-expiry-input" type="datetime-local" value={expires} onChange={e=>setExpires(e.target.value)}/></label><p className="muted">Após o prazo, cada função retorna automaticamente à permissão anterior. Você também pode revogar antes.</p></div>}
  {groupOrder.map(group=><div className="card" key={group}>
   <button type="button" className="btn alt full" aria-expanded={expanded===group} onClick={()=>setExpanded(expanded===group?'':group)}>{group} {expanded===group?'−':'+'}</button>
   {expanded===group&&permRows.filter(r=>r.category===group&&(current?.role!=='desenvolvedor'||r.key==='choose_theme')).map(row=><div className="item" key={row.key} style={{display:'flex',alignItems:'center',justifyContent:'space-between',gap:12}}><div style={{flex:1}}><strong>{row.label}</strong><p className="muted" style={{margin:'2px 0'}}>Padrão do perfil: {row.default?'permitido':'bloqueado'}</p></div><Toggle enabled={getState(row.key,Boolean(row.enabled))} onChange={()=>toggle(row.key,Boolean(row.enabled))} label={row.label}/></div>)}
  </div>)}
  {section==='temporarias'&&<div className="card"><h3>Permissões temporárias ativas</h3>
   {validRules.length===0?<p className="muted">Nenhuma concessão temporária ativa para este usuário.</p>:<>
    <div className="btnrow"><button type="button" className="btn alt" disabled={working} onClick={()=>setSelectedRevokes(Object.fromEntries(validRules.map(rule=>[String(rule.id),true])))}>Selecionar todas</button>
    <button type="button" className="btn alt" disabled={working} onClick={()=>setSelectedRevokes({})}>Limpar seleção</button></div>
    <p className="muted">Marque as permissões que deseja revogar. A revogação será feita de uma só vez e registrada como uma operação na auditoria.</p>
    {validRules.map(rule=><label className="item permission-bulk-item" key={rule.id}><input type="checkbox" disabled={working} checked={!!selectedRevokes[rule.id]} onChange={e=>setSelectedRevokes(previous=>({...previous,[rule.id]:e.target.checked}))}/><span><strong>{permRows.find(p=>p.key===rule.permission_key)?.label||rule.permission_key}</strong><span className="muted" style={{display:'block'}}>{rule.allowed?'Permitida':'Bloqueada'} até {localDate(rule.expires_at)}</span></span></label>)}
    <button type="button" className="btn danger full" disabled={working||confirmName!=='DESENVOLVEDOR'||validRules.filter(rule=>selectedRevokes[rule.id]).length===0} onClick={()=>void revokeBulk()}>{working?'Revogando…':`Revogar selecionadas (${validRules.filter(rule=>selectedRevokes[rule.id]).length})`}</button>
   </>}</div>}
  </>}
  <div className="card"><h3>Confirmar alterações</h3><label className="field">Digite DESENVOLVEDOR<input value={confirmName} autoComplete="off" placeholder="DESENVOLVEDOR" onChange={e=>setConfirmName(e.target.value)}/></label>
   <button type="button" className="btn full" disabled={!hasChanges||working||confirmName!=='DESENVOLVEDOR'||(section==='temporarias'&&!expires)} onClick={()=>void save()}>{working?'Salvando…':`Salvar alterações (${Object.keys(changes).length})`}</button>
   {!hasChanges&&<p className="muted">Nenhuma alteração pendente.</p>}
   {error&&<p role="alert" style={{color:'#b3261e'}}>{error}</p>}{success&&<p role="status" style={{color:'#287a43'}}>{success}</p>}
  </div>
 </div>;
}
