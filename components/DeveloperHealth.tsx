'use client';
import {useCallback,useEffect,useState} from 'react';
import type {SupabaseClient} from '@supabase/supabase-js';
import {Activity,Database,AlertTriangle,RefreshCw,History,HardDrive} from 'lucide-react';

type TableUsage={name:string;bytes:number};
type Snapshot={date:string;bytes:number};
type NeonHealth={
 sampled_at:string;db_bytes:number;reference_limit_bytes:number;reference_kind:string;
 used_pct_reference:number;capacity_score:number;connections:number;deadlocks_total:number;
 previous_date:string|null;previous_bytes:number|null;estimated_days_to_limit:number|null;
 top_tables:TableUsage[];history:Snapshot[];
};
type GitHubIssue={id:number;title:string;url:string;state:string;updated_at:string;kind:string};
type GithubResponse={connected:boolean;issues:GitHubIssue[];reason?:string;checked_at?:string};
type VercelProblem={id:string;title:string;url:string;state:string;updated_at:string};
type VercelResponse={connected:boolean;issues:VercelProblem[];reason?:string;checked_at?:string};
const mb=(bytes:number)=>bytes>=1073741824?(bytes/1073741824).toFixed(2)+' GB':bytes>=1048576?(bytes/1048576).toFixed(2)+' MB':(bytes/1024).toFixed(1)+' KB';
const dateTime=(s:string)=>new Date(s).toLocaleString('pt-BR',{timeZone:'America/Sao_Paulo',dateStyle:'short',timeStyle:'short'});

export default function DeveloperHealth({db}: {db:SupabaseClient|null}) {
 const [health,setHealth]=useState<NeonHealth|null>(null);
 const [github,setGithub]=useState<GithubResponse|null>(null);
 const [vercel,setVercel]=useState<VercelResponse|null>(null);
 const [loading,setLoading]=useState(false),[issueLoading,setIssueLoading]=useState(false);
 const [error,setError]=useState('');
 const load=useCallback(async()=>{
  if(!db)return;
  setLoading(true);setError('');
  try{
   const {data,error}=await db.rpc('developer_neon_health' as never);
   if(error)throw error;
   setHealth(data as NeonHealth);
  }catch{setError('Não foi possível consultar a saúde do Neon. Verifique a conexão ou as permissões.')}
  finally{setLoading(false)}
 },[db]);
 const loadVercel=useCallback(async()=>{
  try{
   const response=await fetch('/api/developer/vercel-problems',{credentials:'same-origin',cache:'no-store'});
   if(!response.ok)throw Error('Consulta indisponível');
   setVercel(await response.json() as VercelResponse);
  }catch{setVercel({connected:false,issues:[],reason:'Não foi possível consultar a Vercel.'})}
 },[]);
 const loadGithub=useCallback(async()=>{
  setIssueLoading(true);
  try{
   const response=await fetch('/api/developer/github-problems',{credentials:'same-origin',cache:'no-store'});
   if(!response.ok)throw Error('Consulta indisponível');
   setGithub(await response.json() as GithubResponse);
  }catch{setGithub({connected:false,issues:[],reason:'Não foi possível consultar o GitHub.'})}
  finally{setIssueLoading(false)}
 },[]);
 useEffect(()=>{void load();void loadGithub();void loadVercel()},[load,loadGithub,loadVercel]);
 const pct=Math.min(100,Math.max(0,Number(health?.used_pct_reference)||0));
 const status=pct>=85?'Uso alto':pct>=65?'Atenção':'Dentro da referência';
 const last=health?.history||[];
 const trend=health?.previous_bytes!=null?Number(health.db_bytes)-Number(health.previous_bytes):null;
 return <section className="card" style={{minWidth:0}}>
  <h3 style={{display:'flex',alignItems:'center',gap:8}}><Activity size={19}/> Saúde do sistema</h3>
  <p className="muted">Neon, GitHub e Vercel em um só lugar.</p>
  <div className="btnrow">
   <button type="button" className="btn alt" onClick={()=>void load()} disabled={loading}><RefreshCw size={15}/>{loading?' Consultando…':' Atualizar Neon'}</button>
   <button type="button" className="btn alt" onClick={()=>{void loadGithub();void loadVercel();void load()}} disabled={issueLoading}>{issueLoading?'Consultando…':'Atualizar problemas'}</button>
  </div>
  {error&&<p role="alert" className="notice error">{error}</p>}
  {health&&<>
   <h4 style={{display:'flex',gap:8,alignItems:'center',marginBottom:8}}><Database size={17}/> Neon — Banco coroinhas</h4>
   <p className="muted">Leitura: {dateTime(health.sampled_at)}</p>
   <div className="developer-metrics">
    <div className="metric"><strong>{mb(health.db_bytes)}</strong><small>Tamanho PostgreSQL</small></div>
    <div className="metric"><strong>{mb(health.reference_limit_bytes)}</strong><small>Referência de espaço</small></div>
    <div className="metric"><strong>{Number(health.capacity_score).toFixed(1)} / 100</strong><small>Espaço disponível (índice)</small></div>
    <div className="metric"><strong>{health.connections}</strong><small>Conexões no momento</small></div>
   </div>
   <div style={{marginTop:14}}>
    <div style={{display:'flex',justifyContent:'space-between',gap:8,flexWrap:'wrap'}}>
     <strong>Uso do espaço</strong><span>{pct.toFixed(2)}% · {status}</span>
    </div>
    <div role="progressbar" aria-label="Consumo estimado em relação ao limite de armazenamento" aria-valuenow={pct} aria-valuemin={0} aria-valuemax={100} style={{height:11,background:'#f3e3e7',borderRadius:20,overflow:'hidden',marginTop:7}}>
     <div style={{height:'100%',width:pct+'%',background:pct>=85?'#b42318':pct>=65?'#be7b18':'#87263d'}}/>
    </div>
    
   </div>
   <div style={{marginTop:12}}>
    <strong>Crescimento e alertas</strong>
    <p className="muted">{trend===null?'Crescimento: aguardando dados.':`Variação: ${trend<0?'-':'+'}${mb(Math.abs(trend))}.`}</p>
    <p className="muted">{health.estimated_days_to_limit!=null?`Estimativa até o limite: ${health.estimated_days_to_limit} dias, se o ritmo continuar.`:'Previsão de limite: indisponível.'}</p>
    <p className="muted">Deadlocks acumulados: {health.deadlocks_total}.</p>
   </div>
   <h4 style={{display:'flex',gap:8,alignItems:'center',marginTop:18}}><HardDrive size={17}/> Tabelas que mais ocupam espaço</h4>
   <div style={{display:'grid',gap:9}}>
    {(health.top_tables||[]).map(t=><div key={t.name} style={{minWidth:0}}>
     <div style={{display:'flex',justifyContent:'space-between',gap:8,fontSize:12}}>
      <span style={{overflowWrap:'anywhere'}}>{t.name}</span><strong style={{whiteSpace:'nowrap'}}>{mb(t.bytes)}</strong>
     </div>
     <div style={{background:'#f3e3e7',height:6,borderRadius:8,overflow:'hidden',marginTop:4}}><div style={{background:'#87263d',height:'100%',width:Math.min(100,100*t.bytes/Math.max(1,health.top_tables[0]?.bytes||1))+'%'}}/></div>
    </div>)}
   </div>
   
   <h4 style={{display:'flex',alignItems:'center',gap:8}}><History size={17}/> Histórico de armazenamento</h4>
   {last.length<=1?<p className="muted">Histórico em formação.</p>:<div style={{display:'flex',alignItems:'flex-end',gap:3,height:76}}>
    {[...last].reverse().map((s,i)=><div key={i} title={dateTime(s.date)+' — '+mb(s.bytes)} style={{flex:1,background:'#87263d',borderRadius:'3px 3px 0 0',height:Math.max(3,100*s.bytes/Math.max(1,...last.map(x=>x.bytes)))+'%'}}/>)}
   </div>}
  </>}
  <h4 style={{display:'flex',gap:8,alignItems:'center',marginTop:18}}><AlertTriangle size={17}/> Problemas do sistema</h4>
  
  <div style={{display:'grid',gap:9}}>
   <div style={{border:'1px solid #ead9dc',padding:12,borderRadius:12,minWidth:0}}>
    <strong>GitHub</strong>
    {!github?<p className="muted">Consultando…</p>:github.connected?
      github.issues.length===0?<p className="muted">Nenhum problema registrado retornado.</p>:
      <div style={{display:'grid',gap:7,marginTop:8}}>{github.issues.map(x=><a key={x.kind+x.id} href={x.url} target="_blank" rel="noopener noreferrer" style={{display:'block',overflowWrap:'anywhere'}}>
       <strong style={{fontSize:13}}>{x.title}</strong><div className="muted" style={{fontSize:12}}>{x.kind} · {x.state} · {dateTime(x.updated_at)}</div>
      </a>)}</div>
      :<p className="muted">Consulta pendente: {github.reason||'Acesso não configurado.'}</p>}
   </div>
   <div style={{border:'1px solid #ead9dc',padding:12,borderRadius:12,minWidth:0}}>
    <strong>Vercel</strong>
    {!vercel?<p className="muted">Consultando…</p>:vercel.connected?
      vercel.issues.length===0?<p className="muted">Nenhum deploy com falha entre os últimos consultados.</p>:
      <div style={{display:'grid',gap:7,marginTop:8}}>{vercel.issues.map(x=><a key={x.id} href={x.url} target="_blank" rel="noopener noreferrer" style={{display:'block',overflowWrap:'anywhere'}}>
       <strong style={{fontSize:13}}>{x.title}</strong><div className="muted" style={{fontSize:12}}>{x.state} · {dateTime(x.updated_at)}</div>
      </a>)}</div>
      :<p className="muted">Consulta pendente: {vercel.reason||'Acesso não configurado.'}</p>}
   </div>
   <div style={{border:'1px solid #ead9dc',padding:12,borderRadius:12,minWidth:0}}>
    <strong>Neon</strong>
    {!health?<p className="muted">{error||'Aguardando consulta ao banco…'}</p>:<>
     <p className="muted">{pct>=85?'Alerta: armazenamento próximo do limite.':pct>=65?'Atenção ao uso de armazenamento.':'Espaço dentro da referência.'}</p>
     <p className="muted">{Number(health.deadlocks_total)>0?'Deadlocks acumulados: '+health.deadlocks_total+'.':'Sem deadlocks acumulados.'}</p>
     <p className="muted">Última leitura: {dateTime(health.sampled_at)}</p>
    </>}
   </div>
  </div>
  <p className="muted" style={{fontSize:12}}>Exibe apenas os problemas disponíveis nas consultas.</p>
 </section>;
}
