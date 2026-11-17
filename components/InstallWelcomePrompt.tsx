'use client';
import {useEffect,useState} from 'react';
import type {SupabaseClient} from '@supabase/supabase-js';
import {BellRing,Smartphone,X} from 'lucide-react';

export const NOTIFICATION_ONBOARDING_TITLE='Ative as notificações — orientação de instalação';

function isInstalled(){
 return window.matchMedia('(display-mode: standalone)').matches||
  Boolean((navigator as Navigator&{standalone?:boolean}).standalone);
}

export default function InstallWelcomePrompt({userId,db,pushEnabled,onOpenSettings}:{userId:string;db:SupabaseClient|null;pushEnabled:boolean;onOpenSettings:()=>void}){
 const [visible,setVisible]=useState(false);
 const [step,setStep]=useState<'intro'|'needs-install'>('intro');
 const [platform,setPlatform]=useState<'ios'|'android'>('android');

 useEffect(()=>{
  if(!db||!userId)return;
  let alive=true;
  const ua=navigator.userAgent||'';
  const ios=/iPad|iPhone|iPod/i.test(ua)||(/Macintosh/i.test(ua)&&navigator.maxTouchPoints>1);
  const android=/Android/i.test(ua);
  if(!ios&&!android)return;
  setPlatform(ios?'ios':'android');
  const closed=()=>{if(alive)setVisible(false)};
  window.addEventListener('esb-onboarding-ended',closed);

  (async()=>{
   try{
    // O desenvolvedor encerra a campanha pelo item em Enviadas > Mensagens pop-up.
    const {data,error}=await db.from('screen_announcements')
     .select('id,active').eq('title',NOTIFICATION_ONBOARDING_TITLE).eq('active',true).limit(1);
    if(error||!data?.length||!alive)return;

    // Só parar de mostrar depois que a inscrição push estiver de fato ativa no aparelho.
    if(!('serviceWorker' in navigator))return void(alive&&setVisible(true));
    const registration=await navigator.serviceWorker.getRegistration('/push-sw.js');
    const subscription=await registration?.pushManager.getSubscription().catch(()=>null);
    if(!alive)return;
    if(subscription){setVisible(false);return;}
    setStep('intro');
    setVisible(true);
   }catch{
    // Falha de comunicação não autoriza mostrar aviso de campanha possivelmente encerrada.
   }
  })();
  return()=>{alive=false;window.removeEventListener('esb-onboarding-ended',closed)};
 },[db,userId]);

 useEffect(()=>{if(pushEnabled)setVisible(false)},[pushEnabled]);

 const close=()=>setVisible(false); // Apenas nesta entrada; a próxima entrada exibirá de novo.
 const go=()=>{close();onOpenSettings()};
 const activate=()=>{
  if(isInstalled()){go();return;}
  setStep('needs-install'); // Não redirecionar automaticamente: permitir a leitura.
 };
 if(!visible||pushEnabled)return null;
 return <div className="install-welcome-overlay" role="presentation">
  <section className="install-welcome-card" role="dialog" aria-modal="true" aria-labelledby="install-welcome-title" aria-describedby="install-welcome-description">
   <button type="button" className="install-welcome-x" aria-label="Fechar aviso nesta entrada" onClick={close}><X size={20}/></button>
   <div className="install-welcome-icon">{step==='intro'?<BellRing size={30}/>:<Smartphone size={30}/>}</div>
   {step==='intro'?<>
    <h2 id="install-welcome-title">Ative as notificações!</h2>
    <p id="install-welcome-description">Receba avisos sobre escalas, substituições e mensagens importantes diretamente no celular.</p>
    <button type="button" className="btn full install-welcome-action" onClick={activate}><BellRing size={18}/> Ativar notificações</button>
    <button type="button" className="btn alt full install-welcome-later" onClick={close}>Agora não</button>
   </>:<>
    <h2 id="install-welcome-title">Primeiro, adicione o aplicativo</h2>
    <p id="install-welcome-description">{platform==='ios'?'No iPhone, abra o Escalas São Bento no Safari e adicione-o à Tela de Início antes de ativar as notificações.':'No Android, instale o aplicativo pelo Chrome para receber as notificações com mais facilidade.'}</p>
    <p className="install-welcome-tip">Em <strong>Ajustes</strong>, há um passo a passo para {platform==='ios'?'iPhone':'Android'}. Leia com calma e toque no botão abaixo quando estiver pronto.</p>
    <button type="button" className="btn full install-welcome-action" onClick={go}>Ir para Ajustes</button>
    <button type="button" className="btn alt full install-welcome-later" onClick={close}>Agora não</button>
   </>}
  </section>
 </div>;
}
