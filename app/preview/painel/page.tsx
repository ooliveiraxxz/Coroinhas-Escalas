import type {Metadata} from 'next';

export const metadata:Metadata={title:'Prévia do painel — Escalas São Bento',robots:{index:false,follow:false}};

const metrics:[string,string][]=[
 ['20','Usuários'],['18','Aprovados'],['2','Pendentes'],
 ['11','Coroinhas'],['3','Cerimoniários'],['2','Responsáveis'],
 ['1','Coordenadores(as)'],['1','Desenvolvedores'],
 ['4','Aparelhos com notificações ativadas'],
 ['4','Usuários com notificações ativadas'],
 ['14','Aprovados sem notificações ativadas']
];
export default function PreviewPanel(){
 return <main className="preview-panel">
  <style>{`
  .preview-panel{min-height:100vh;background:#faf7f6;color:#4a393d;font-family:Arial,Helvetica,sans-serif;padding:20px 18px 95px}
  .preview-panel *{box-sizing:border-box}
  .preview-panel .preview-wrap{max-width:580px;margin:0 auto}
  .preview-panel h1{font-size:23px;color:#801d38;margin:8px 0 8px}
  .preview-panel p{line-height:1.5;font-size:14px}
  .preview-panel .demo-banner{background:#fff1e7;border:1px solid #e6ad79;color:#613a19;border-radius:14px;padding:12px;font-weight:700;font-size:13px;line-height:1.55;margin-bottom:19px}
  .preview-panel .preview-grid{display:grid;grid-template-columns:1fr 1fr;gap:12px}
  .preview-panel .metric{border:1px solid #e6dad8;border-radius:20px;background:white;min-height:124px;padding:17px 8px;display:flex;flex-direction:column;align-items:center;justify-content:center;text-align:center;gap:9px}
  .preview-panel .metric strong{font-size:32px;color:#891e3f}
  .preview-panel .metric span{font-size:15px;font-weight:600;color:#73676b;line-height:1.3}
  .preview-panel .highlight{border-color:#bc8b99;background:#fffafb}
  .preview-panel .section{font-weight:700;margin:24px 0 14px;color:#801d38}
  .preview-panel .footnote{font-size:12px;color:#6d6366;margin-top:18px}
  @media(max-width:370px){.preview-panel .metric span{font-size:13px}.preview-panel .preview-grid{gap:9px}}
  `}</style>
  <div className="preview-wrap">
   <div className="demo-banner">DEMONSTRAÇÃO SEGURA — os números abaixo são um retrato da consulta anterior. Esta página não acessa cadastros nem altera o banco oficial.</div>
   <h1>Painel do Desenvolvedor</h1>
   <p>Visualização dos indicadores do Escalas São Bento. Os novos cartões mostram quem já habilitou notificações no aparelho.</p>
   <div className="preview-grid">{metrics.slice(0,8).map(([value,label])=><div className="metric" key={label}><strong>{value}</strong><span>{label}</span></div>)}</div>
   <h2 className="section">Notificações nos aparelhos</h2>
   <div className="preview-grid">{metrics.slice(8).map(([value,label])=><div className="metric highlight" key={label}><strong>{value}</strong><span>{label}</span></div>)}</div>
   <p className="footnote">O aplicativo instalado na tela inicial e a permissão de notificações são informações diferentes. Sem telemetria de instalação, o número de instalações PWA não pode ser medido com precisão.</p>
   <p className="footnote">Visualização de teste sem login. Na versão final, esses indicadores aparecerão no painel existente e serão atualizados com os dados autorizados do banco.</p>
  </div>
 </main>
}