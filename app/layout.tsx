import './globals.css';
import Script from 'next/script';
import type {Metadata, Viewport} from 'next';
export const metadata:Metadata={title:'Escala São Bento',applicationName:'Escala São Bento',description:'Escalas de coroinhas, celebrações e comunicados da coordenação',manifest:'/manifest.webmanifest',appleWebApp:{capable:true,statusBarStyle:'default',title:'Escala São Bento'},icons:{icon:[{url:'/icon.svg',type:'image/svg+xml'}],apple:'/apple-icon.png'}};
export const viewport:Viewport={themeColor:'#751e33',width:'device-width',initialScale:1};
export default function RootLayout({children}:{children:React.ReactNode}){return <html lang="pt-BR"><body><Script id="install-prompt-early" strategy="beforeInteractive">{`(function(){if(window.__esbInstallListenerReady)return;window.__esbInstallListenerReady=true;window.addEventListener('beforeinstallprompt',function(event){event.preventDefault();window.__esbInstallPrompt=event;window.dispatchEvent(new Event('esb-install-prompt-ready'));});window.addEventListener('appinstalled',function(){window.__esbInstallPrompt=null;window.dispatchEvent(new Event('esb-app-installed'));});})();`}</Script>{children}</body></html>}
