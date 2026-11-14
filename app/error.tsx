'use client';
import {useEffect} from 'react';

export default function Error({error,reset}:{error:Error&{digest?:string};reset:()=>void}){
 useEffect(()=>{console.error('Falha ao abrir o Escalas São Bento:',error);},[error]);
 return <main style={{minHeight:'100dvh',display:'flex',alignItems:'center',justifyContent:'center',padding:24,background:'#fffaf7',color:'#30252a',fontFamily:'-apple-system,BlinkMacSystemFont,Arial,sans-serif'}}>
  <section style={{maxWidth:370,width:'100%',textAlign:'center'}}>
   <h1 style={{fontSize:24,marginBottom:12}}>Escala São Bento</h1>
   <h2 style={{fontSize:18,fontWeight:600}}>Não foi possível carregar o aplicativo.</h2>
   <p style={{lineHeight:1.5}}>Verifique a conexão e toque em tentar novamente. Seus dados e sua conta estão preservados.</p>
   <button type="button" onClick={()=>reset()} style={{background:'#751e33',border:0,color:'#fff',padding:'14px 20px',borderRadius:10,fontWeight:600,width:'100%',fontSize:16}}>Tentar novamente</button>
   <button type="button" onClick={()=>window.location.reload()} style={{marginTop:12,background:'transparent',border:'1px solid #751e33',color:'#751e33',padding:'13px 20px',borderRadius:10,width:'100%',fontSize:16}}>Recarregar aplicativo</button>
   <p style={{fontSize:12,opacity:.7,marginTop:18}}>Se continuar, abra coroinhas-escalas.vercel.app no Safari.</p>
  </section>
 </main>;
}
