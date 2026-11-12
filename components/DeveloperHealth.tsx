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
const mb=(bytes:number)=>bytes>=1048576?(bytes/1048576).toFixed(2)+' MiB':(bytes/1024).toFixed(1)+' KiB';
const dateTime=(s:string)=>new Date(s).toLocaleString('pt-BR',{timeZone:'America/Sao_Paulo',dateStyle:'short',timeStyle:'short'});

export default function DeveloperHealth({db}: {db:SupabaseClient|null}) {
 const [health,setHealth]=useState<NeonHealth|null>(null);
 const [github,setGithub]=useState<GithubResponse|null>(null);
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
 const loadGithub=useCallback(async()=>{
  setIssueLoading(true);
  try{
   const response=await fetch('/api/developer/github-problems',{credentials:'same-origin',cache:'no-store'});
   if(!response.ok)throw Error('Consulta indisponível');
   setGithub(await response.json() as GithubResponse);
  }catch{setGithub({connected:false,issues:[],reason:'Não foi possível consultar o GitHub.'})}
  finally{setIssueLoading(false)}
 },[]);
 useEffect(()=>{void load();void loadGithub()},[load,loadGithub]);
 const pct=Math.min(100,Math.max(0,Number(health?.used_pct_reference)||0));
 const status=pct>=85?'Uso alto':pct>=65?'Atenção':'Dentro da referência';
 const last=health?.history||[];
 const trend=health?.previous_bytes!=null?Number(health.db_bytes)-Number(health.previous_bytes):null;
 return <section className="card" style={{minWidth:0}}>
  <h3 style={{display:'flex',alignItems:'center',gap:8}}><Activity size={19}/> Saúde do sistema</h3>
  <p className="muted">Indicadores reais do Neon e histórico de problemas do GitHub. A capacidade é uma estimativa, não uma medição de temperatura ou de disponibilidade.</p>
  <div className="btnrow">
   <button type="button" className="btn alt" onClick={()=>void load()} disabled={loading}><RefreshCw size={15}/>{loading?' Consultando…':' Atualizar Neon'}</button>
   <button type="button" className="btn alt" onClick={()=>void loadGithub()} disabled={issueLoading}>{issueLoading?'Consultando GitHub…':'Atualizar problemas'}</button>
  </div>
  {error&&<p role="alert" className="notice error">{error}</p>}
  {health&&<>
   <h4 style={{display:'flex',gap:8,alignItems:'center',marginBottom:8}}><Database size={17}/> Neon — Banco coroinhas</h4>
   <p className="muted">Leitura: {dateTime(health.sampled_at)}</p>
   <div className="developer-metrics">
    <div className="metric"><strong>{mb(health.db_bytes)}</strong><small>Tamanho PostgreSQL</small></div>
    <div className="metric"><strong>{mb(health.reference_limit_bytes)}</strong><small>Limite lógico informado</small></div>
    <div className="metric"><strong>{Number(health.capacity_score).toFixed(1)} / 100</strong><small>Índice estimado de espaço livre</small></div>
    <div className="metric"><strong>{health.connections}</strong><small>Conexões no momento</small></div>
   </div>
   <div style={{marginTop:14}}>
    <div style={{display:'flex',justifyContent:'space-between',gap:8,flexWrap:'wrap'}}>
     <strong>Referência de armazenamento</strong><span>{pct.toFixed(2)}% · {status}</span>
    </div>
    <div role="progressbar" aria-label="Consumo estimado em relação ao limite de armazenamento" aria-valuenow={pct} aria-valuemin={0} aria-valuemax={100} style={{height:11,background:'#f3e3e7',borderRadius:20,overflow:'hidden',marginTop:7}}>
     <div style={{height:'100%',width:pct+'%',background:pct>=85?'#b42318':pct>=65?'#be7b18':'#87263d'}}/>
    </div>
    <p className="muted" style={{fontSize:12}}>O tamanho retornado pelo PostgreSQL é comparado com o limite lógico de 1 GiB do projeto. A cobrança e o consumo real do Neon podem usar outra métrica; esta porcentagem é apenas indicativa.</p>
   </div>
   <div style={{marginTop:12}}>
    <strong>Crescimento e sinais de alerta</strong>
    <p className="muted">{trend===null?'Ainda não há amostras com 24 horas de diferença para prever crescimento.':`Variação desde ${dateTime(health.previous_date!)}: ${trend>=0?'+':''}${mb(Math.abs(trend))}${trend<0?' (redução)':''}.`}</p>
    <p className="muted">{health.estimated_days_to_limit!=null?`Projeção matemática até a referência: aproximadamente ${health.estimated_days_to_limit} dias, se o crescimento observado continuar.`:'Sem dados suficientes para prever quando o espaço será preenchido.'}</p>
    <p className="muted">Deadlocks registrados desde o último reset das estatísticas: {health.deadlocks_total}. Não há medição de CPU/temperatura neste painel.</p>
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
   <p className="muted" style={{fontSize:12}}>Inclui dados, índices e overhead por tabela. O tamanho total do banco inclui também componentes internos do PostgreSQL.</p>
   <h4 style={{display:'flex',alignItems:'center',gap:8}}><History size={17}/> Histórico de armazenamento</h4>
   {last.length<=1?<p className="muted">A primeira amostra foi registrada. Novos pontos serão coletados diariamente.</p>:<div style={{display:'flex',alignItems:'flex-end',gap:3,height:76}}>
    {[...last].reverse().map((s,i)=><div key={i} title={dateTime(s.date)+' — '+mb(s.bytes)} style={{flex:1,background:'#87263d',borderRadius:'3px 3px 0 0',height:Math.max(3,100*s.bytes/Math.max(1,...last.map(x=>x.bytes)))+'%'}}/>)}
   </div>}
  </>}
  <h4 style={{display:'flex',gap:8,alignItems:'center',marginTop:18}}><AlertTriangle size={17}/> Problemas relatados — GitHub</h4>
  {github?.connected?<>
    <p className="muted">Issues e execuções de workflow com falha, incluindo registros já encerrados. Atualizado em {github.checked_at?dateTime(github.checked_at):'—'}.</p>
    {github.issues.length===0?<p className="muted">Nenhum registro retornado na consulta.</p>:<div style={{display:'grid',gap:8}}>{github.issues.map(x=><a key={x.kind+x.id} href={x.url} target="_blank" rel="noopener noreferrer" style={{border:'1px solid #ead9dc',padding:9,borderRadius:10,display:'block',overflowWrap:'anywhere'}}>
     <strong>{x.title}</strong><div className="muted" style={{fontSize:12}}>{x.kind} · {x.state} · {dateTime(x.updated_at)}</div>
    </a>)}</div>}
   </>:<p className="muted">{github?.reason||'Consultando problemas…'} O GitHub só aparecerá conectado quando a autenticação de leitura for configurada no servidor.</p>}
 </section>;
}
