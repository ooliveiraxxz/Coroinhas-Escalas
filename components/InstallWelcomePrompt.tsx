'use client';
import {useEffect,useRef,useState} from 'react';
import {BellRing,Smartphone,X} from 'lucide-react';

function isInstalled(){
 return window.matchMedia('(display-mode: standalone)').matches||
  Boolean((navigator as Navigator&{standalone?:boolean}).standalone);
}
export default function InstallWelcomePrompt({userId,onOpenSettings}:{userId:string;onOpenSettings:()=>void}){
 const [visible,setVisible]=useState(false);
 const [step,setStep]=useState<'intro'|'needs-install'>('intro');
 const [platform,setPlatform]=useState<'ios'|'android'>('android');
 const timer=useRef<ReturnType<typeof setTimeout>|null>(null);
 const key='esb-notification-onboarding-v1:'+userId;
 useEffect(()=>{
  if(!userId)return;
  const ua=navigator.userAgent||'';
  const ios=/iPad|iPhone|iPod/i.test(ua)||(/Macintosh/i.test(ua)&&navigator.maxTouchPoints>1);
  const android=/Android/i.test(ua);
  if(!ios&&!android)return;
  setPlatform(ios?'ios':'android');
  try{if(localStorage.getItem(key)==='dismissed')return;}catch{}
  const delay=window.setTimeout(()=>setVisible(true),500);
  return()=>{window.clearTimeout(delay);if(timer.current)clearTimeout(timer.current);};
 },[userId,key]);
 const close=()=>{if(timer.current)clearTimeout(timer.current);setVisible(false);try{localStorage.setItem(key,'dismissed');}catch{}};
 const go=()=>{close();onOpenSettings()};
 const activate=()=>{
  if(isInstalled()){go();return;}
  setStep('needs-install');
  timer.current=setTimeout(go,2200);
 };
 if(!visible)return null;
 return <div className="install-welcome-overlay" role="presentation">
  <section className="install-welcome-card" role="dialog" aria-modal="true" aria-labelledby="install-welcome-title" aria-describedby="install-welcome-description">
   <button type="button" className="install-welcome-x" aria-label="Fechar aviso" onClick={close}><X size={20}/></button>
   <div className="install-welcome-icon">{step==='intro'?<BellRing size={30}/>:<Smartphone size={30}/>}</div>
   {step==='intro'?<>
    <h2 id="install-welcome-title">Ative as notificações!</h2>
    <p id="install-welcome-description">Receba avisos sobre escalas, substituições e mensagens importantes diretamente no celular.</p>
    <button type="button" className="btn full install-welcome-action" onClick={activate}><BellRing size={18}/> Ativar notificações</button>
    <button type="button" className="btn alt full install-welcome-later" onClick={close}>Agora não</button>
   </>:<>
    <h2 id="install-welcome-title">Primeiro, adicione o aplicativo</h2>
    <p id="install-welcome-description">{platform==='ios'?'No iPhone, você precisa adicionar o Escalas São Bento à Tela de Início pelo Safari antes de ativar notificações.':'No Android, adicione ou instale o aplicativo para acessar as notificações com mais facilidade.'}</p>
    <p className="install-welcome-tip">Abrindo <strong>Ajustes</strong>, onde você encontra o passo a passo para {platform==='ios'?'iPhone':'Android'}…</p>
    <button type="button" className="btn full install-welcome-action" onClick={go}>Ir para Ajustes agora</button>
   </>}
  </section>
 </div>;
}
