'use client';
import {useEffect,useState} from 'react';
import {Download,Share2,Smartphone,X} from 'lucide-react';

type InstallPromptEvent=Event & {prompt:()=>Promise<void>;userChoice:Promise<{outcome:'accepted'|'dismissed';platform:string}>};
declare global {interface Window {__esbInstallPrompt?:InstallPromptEvent|null;__esbInstallListenerReady?:boolean;}}

const isStandalone=()=>window.matchMedia('(display-mode: standalone)').matches||
  Boolean((navigator as Navigator & {standalone?:boolean}).standalone);

export default function InstallWelcomePrompt({userId}:{userId:string}){
 const [platform,setPlatform]=useState<'ios'|'android'|null>(null);
 const [visible,setVisible]=useState(false);
 const [installEvent,setInstallEvent]=useState<InstallPromptEvent|null>(null);
 const [message,setMessage]=useState('');
 const [busy,setBusy]=useState(false);
 const [safari,setSafari]=useState(true);
 const key='esb-install-welcome-v1:'+userId;

 useEffect(()=>{
  if(!userId)return;
  const agent=navigator.userAgent||'';
  const ios=/iPad|iPhone|iPod/i.test(agent)||(/Macintosh/i.test(agent)&&navigator.maxTouchPoints>1);
  const android=/Android/i.test(agent);
  // O aviso é para celulares; não cobre a interface em computadores.
  if(!ios&&!android)return;
  setPlatform(ios?'ios':'android');
  setSafari(/Safari/i.test(agent)&&!/CriOS|FxiOS|EdgiOS|OPiOS/i.test(agent));
  if(isStandalone())return;
  try{if(localStorage.getItem(key)==='dismissed')return;}catch{}
  const sync=()=>setInstallEvent(window.__esbInstallPrompt||null);
  const done=()=>{setVisible(false);setInstallEvent(null);try{localStorage.setItem(key,'dismissed')}catch{}};
  sync();
  window.addEventListener('esb-install-prompt-ready',sync);
  window.addEventListener('appinstalled',done);
  window.addEventListener('esb-app-installed',done);
  const timer=window.setTimeout(()=>setVisible(true),400);
  return ()=>{
   window.clearTimeout(timer);
   window.removeEventListener('esb-install-prompt-ready',sync);
   window.removeEventListener('appinstalled',done);
   window.removeEventListener('esb-app-installed',done);
  };
 },[userId,key]);

 const close=()=>{
  setVisible(false);
  try{localStorage.setItem(key,'dismissed')}catch{}
 };
 const install=async()=>{
  if(!installEvent){
   setMessage('No Chrome, toque no menu ⋮ e escolha “Instalar aplicativo” ou “Adicionar à tela inicial”.');
   return;
  }
  setBusy(true);
  const event=installEvent;
  setInstallEvent(null);
  window.__esbInstallPrompt=null;
  try{
   await event.prompt();
   const result=await event.userChoice;
   if(result.outcome==='accepted'){
    setMessage('Instalação aceita! Abra o aplicativo pelo ícone na tela inicial.');
    close();
   }else setMessage('Instalação cancelada. Você ainda pode instalar pelo menu ⋮ do Chrome.');
  }catch{
   setMessage('Não foi possível abrir a instalação automática. Use o menu ⋮ do Chrome.');
  }finally{setBusy(false)}
 };
 if(!visible||!platform)return null;
 return <div className="install-welcome-overlay" role="presentation">
  <section className="install-welcome-card" role="dialog" aria-modal="true" aria-labelledby="install-welcome-title" aria-describedby="install-welcome-description">
   <button type="button" className="install-welcome-x" aria-label="Fechar aviso de instalação" onClick={close}><X size={20}/></button>
   <div className="install-welcome-icon"><Smartphone size={30}/></div>
   <h2 id="install-welcome-title">Tenha o Escalas São Bento na tela inicial!</h2>
   <p id="install-welcome-description">Acesse suas escalas e notificações com mais facilidade, como um aplicativo.</p>
   {platform==='ios'?<>
    {!safari&&<p className="install-welcome-tip">Para adicionar, abra este site no <strong>Safari</strong>.</p>}
    <ol className="install-welcome-steps">
     <li>Abra este site no <strong>Safari</strong>.</li>
     <li>Toque em <Share2 size={17} aria-hidden="true"/> <strong>Compartilhar</strong> (quadrado com seta para cima). Dependendo da versão, abra primeiro o menu da página.</li>
     <li>Escolha <strong>Adicionar à Tela de Início</strong>.</li>
     <li>Toque em <strong>Adicionar</strong> e abra pelo novo ícone.</li>
    </ol>
    <p className="install-welcome-note">No iPhone, a instalação precisa ser confirmada no Safari.</p>
   </>:<>
    <p className="install-welcome-tip">No Android, instale diretamente quando o Chrome disponibilizar essa opção.</p>
    <button type="button" className="btn full install-welcome-action" disabled={busy} onClick={()=>void install()}>
     <Download size={18} aria-hidden="true"/>{busy?'Abrindo instalação…':installEvent?'Instalar aplicativo':'Como instalar no Android'}
    </button>
    <p className="install-welcome-note">Se não abrir automaticamente, no <strong>Chrome</strong> toque em <strong>⋮</strong> e escolha <strong>Instalar aplicativo</strong> ou <strong>Adicionar à tela inicial</strong>.</p>
   </>}
   {message&&<p className="install-welcome-feedback" role="status">{message}</p>}
   <button type="button" className="btn alt full install-welcome-later" onClick={close}>Agora não</button>
  </section>
 </div>;
}
