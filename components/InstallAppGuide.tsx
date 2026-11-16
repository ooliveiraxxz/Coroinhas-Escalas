'use client';
import {useEffect,useState} from 'react';

type InstallPromptEvent = Event & {
  prompt: () => Promise<void>;
  userChoice: Promise<{outcome: 'accepted' | 'dismissed'; platform: string}>;
};

type Platform = 'ios' | 'android';
declare global {
 interface Window { __esbInstallPrompt?: InstallPromptEvent | null; __esbInstallListenerReady?: boolean; }
}
export default function InstallAppGuide(){
 const [platform,setPlatform]=useState<Platform>('ios');
 const [installed,setInstalled]=useState(false);
 const [installPrompt,setInstallPrompt]=useState<InstallPromptEvent|null>(null);
 const [message,setMessage]=useState('');
 const [isSafari,setIsSafari]=useState(true);

 useEffect(()=>{
  const ua=navigator.userAgent||'';
  const ios=/iPad|iPhone|iPod/.test(ua)||(/Macintosh/.test(ua)&&navigator.maxTouchPoints>1);
  setPlatform(ios?'ios':'android');
  setIsSafari(/Safari/i.test(ua)&&!/CriOS|FxiOS|EdgiOS|OPiOS/i.test(ua));
  const standalone=window.matchMedia('(display-mode: standalone)').matches ||
    ('standalone' in navigator && Boolean((navigator as Navigator & {standalone?:boolean}).standalone));
  setInstalled(standalone);
  // O navegador pode disponibilizar a instalação antes de abrir Ajustes.
  // O script inicial em app/layout.tsx guarda o evento para esta tela.
  const syncPrompt=()=>setInstallPrompt(window.__esbInstallPrompt||null);
  const didInstall=()=>{setInstalled(true);setInstallPrompt(null);setMessage('Aplicativo instalado com sucesso neste dispositivo!');};
  syncPrompt();
  window.addEventListener('esb-install-prompt-ready',syncPrompt);
  window.addEventListener('esb-app-installed',didInstall);
  window.addEventListener('appinstalled',didInstall);
  return ()=>{window.removeEventListener('esb-install-prompt-ready',syncPrompt);window.removeEventListener('esb-app-installed',didInstall);window.removeEventListener('appinstalled',didInstall);};
 },[]);

 const install=async()=>{
  if(!installPrompt){setPlatform('android');setMessage('A instalação automática não está disponível neste navegador. Abra o site no Chrome e use o menu ⋮ → Instalar aplicativo ou Adicionar à tela inicial.');return;}
  const event=installPrompt;
  setInstallPrompt(null);
  window.__esbInstallPrompt=null;
  try{
   await event.prompt();
   const choice=await event.userChoice;
   if(choice.outcome==='accepted')setMessage('Pedido de instalação aceito. Confira a tela inicial do celular.');
   else setMessage('Instalação cancelada. Você pode tentar novamente pelo menu do navegador.');
  }catch{
   setMessage('Não foi possível abrir a instalação automática. Use o menu ⋮ do navegador.');
  }
 };

 return <section className="card notification-settings-card" aria-label="Instalar Escalas São Bento">
   <h3>Instalar Escalas São Bento</h3>
   {installed?<>
     <p role="status">✓ Você já está usando o aplicativo pela tela inicial deste dispositivo.</p>
     <p className="muted">Você pode continuar usando normalmente e configurar as notificações abaixo.</p>
   </>:<>
     <p className="muted">Adicione o Escalas São Bento à tela inicial e abra como um aplicativo, sem precisar procurar o site toda vez.</p>
     <div className="btnrow" role="group" aria-label="Escolha seu celular" style={{marginBottom:12}}>
       <button type="button" className={platform==='ios'?'btn':'btn alt'} onClick={()=>{setPlatform('ios');setMessage('');}}>iPhone</button>
       <button type="button" className={platform==='android'?'btn':'btn alt'} onClick={()=>{setPlatform('android');setMessage('');}}>Android</button>
     </div>
     {platform==='ios'?<>
       <p><strong>Instalar no iPhone</strong></p>
       {!isSafari&&<p className="muted">Se a opção não aparecer neste navegador, abra o site no Safari.</p>}
       <ol style={{paddingLeft:22,lineHeight:1.8}}>
         <li>Abra este site no <strong>Safari</strong>.</li>
         <li>Toque no ícone de <strong>Compartilhar</strong> (quadrado com seta para cima). Em algumas versões, toque antes no menu da página.</li>
         <li>Selecione <strong>Adicionar à Tela de Início</strong>.</li>
         <li>Se aparecer, marque <strong>Abrir como App</strong> e toque em <strong>Adicionar</strong>.</li>
       </ol>
       <p className="muted">Por segurança do iPhone, nenhum site consegue adicionar o ícone automaticamente: a confirmação é feita no Safari.</p>
     </>:<>
       <p><strong>Instalar no Android</strong></p>
       <button type="button" className="btn full" onClick={()=>void install()}>{installPrompt?'Instalar aplicativo agora':'Ver como instalar no Android'}</button>
       <ol style={{paddingLeft:22,lineHeight:1.8}}>
         <li>Abra <strong>coroinhas-escalas.vercel.app</strong> no <strong>Google Chrome</strong>, fora de aplicativos como WhatsApp ou Instagram.</li>
         <li>{installPrompt?'Toque em “Instalar aplicativo agora” acima e confirme.':'Toque no menu ⋮ do navegador.'}</li>
         <li>{installPrompt?'O aplicativo aparecerá na tela inicial.':'Escolha “Instalar aplicativo” ou “Adicionar à tela inicial” e confirme.'}</li>
       </ol>
     </>}
     {platform==='android'&&!installPrompt&&<p className="muted" role="status">Se o botão de instalação automática não aparecer, use o menu ⋮ do Chrome. O navegador precisa permitir a instalação; o site não consegue forçar essa janela.</p>}
     {message&&<p role="status" className="muted">{message}</p>}
     <p className="muted">Depois de adicionar o ícone, abra o aplicativo por ele para acessar as notificações e suas escalas.</p>
   </>}
 </section>;
}
