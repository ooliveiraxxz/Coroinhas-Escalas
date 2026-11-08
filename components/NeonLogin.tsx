'use client';
import {useState} from 'react';
import {Church,Eye,EyeOff} from 'lucide-react';
import {neonAuth} from '@/lib/auth/client';
import {refreshNeonSession} from '@/lib/neon/client';
export default function NeonLogin(){
 const [mode,setMode]=useState<'login'|'signup'|'reset'|'reset-code'>('login');
 const [email,setEmail]=useState(''),[name,setName]=useState(''),[password,setPassword]=useState(''),[otp,setOtp]=useState(''),[role,setRole]=useState('coroinha'),[busy,setBusy]=useState(false),[error,setError]=useState(''),[visible,setVisible]=useState(false),[notice,setNotice]=useState('');
 async function submit(){
  setBusy(true);setError('');setNotice('');
  try{
   let result;
   if(mode==='signup'){
    result=await neonAuth.signUp.email({email,password,name});if(result.error)throw new Error(result.error.message);
    const current=await neonAuth.getSession();
    if(!current.data?.user?.id||current.data.user.id!==result.data?.user?.id){
     const signed=await neonAuth.signIn.email({email,password});
     if(signed.error){setMode('login');setNotice('Conta criada. Entre com sua senha para solicitar aprovação.');return;}
    }
    await refreshNeonSession(role);return;
   }
   if(mode==='reset'){
    result=await neonAuth.emailOtp.sendVerificationOtp({email,type:'forget-password'});if(result.error)throw new Error(result.error.message);
    setMode('reset-code');setNotice('Se a conta existir, confira seu e-mail.');return;
   }
   if(mode==='reset-code'){
    result=await neonAuth.emailOtp.resetPassword({email,otp,password});if(result.error)throw new Error(result.error.message);
    setMode('login');setPassword('');setOtp('');setNotice('Senha definida. Entre na sua conta.');return;
   }
   result=await neonAuth.signIn.email({email,password});if(result.error)throw new Error(result.error.message);
   await refreshNeonSession(role);
  }catch(e){setError(e instanceof Error?e.message:'Não foi possível concluir.')}finally{setBusy(false)}
 }
 async function sendMagicLink(){
  const target=email.trim().toLowerCase();
  if(!target){setError('Informe seu e-mail para receber o link de acesso.');return}
  setBusy(true);setError('');setNotice('');
  try{
   const result=await neonAuth.signIn.magicLink({email:target,callbackURL:window.location.origin});
   if(result.error)throw new Error(result.error.message||'Não foi possível enviar o link.');
   setNotice('Se este e-mail já possui conta, confira a caixa de entrada e o spam. O link expira em 10 minutos.');
  }catch(e){setError(e instanceof Error?e.message:'Não foi possível enviar o link.')}
  finally{setBusy(false)}
 }
 const title={login:'Entrar',signup:'Criar conta',reset:'Ativar conta / recuperar senha','reset-code':'Definir senha'}[mode];
 return <div className="auth"><div className="auth-brand"><div className="brand-symbol"><Church size={44}/></div><h1>Coroinhas</h1><p>Escalas e organização das celebrações</p></div><div className="auth-box"><h2>{title}</h2>
 <form onSubmit={e=>{e.preventDefault();void submit()}}>
 {mode==='signup'&&<><label className="field">Nome completo<input required value={name} onChange={e=>setName(e.target.value)}/></label><label className="field">Tipo de cadastro<select value={role} onChange={e=>setRole(e.target.value)}><option value="coroinha">Sou coroinha</option><option value="pai">Sou pai, mãe ou responsável</option></select></label></>}
 <label className="field">E-mail<input required type="email" autoComplete="email" value={email} onChange={e=>setEmail(e.target.value)}/></label>
 {mode==='reset-code'&&<label className="field">Código recebido<input required inputMode="numeric" autoComplete="one-time-code" value={otp} onChange={e=>setOtp(e.target.value)}/></label>}
 {mode!=='reset'&&<label className="field">{mode==='reset-code'?'Nova senha':'Senha'}<div className="password-field"><input required minLength={8} type={visible?'text':'password'} autoComplete={mode==='login'?'current-password':'new-password'} value={password} onChange={e=>setPassword(e.target.value)}/><button type="button" className="password-toggle" aria-label={visible?'Ocultar senha':'Mostrar senha'} onClick={()=>setVisible(!visible)}>{visible?<EyeOff size={21}/>:<Eye size={21}/>}</button></div></label>}
 <button className="btn full" disabled={busy}>{busy?'Aguarde…':title}</button></form>
 <button className="btn alt full" disabled={busy} style={{marginTop:12}} onClick={()=>{setMode(mode==='login'?'signup':'login');setError('');setNotice('')}}>{mode==='login'?'Criar conta / Solicitar acesso':'Voltar ao login'}</button>
 {mode==='login'&&<button className="btn neutral full" type="button" disabled={busy||!email.trim()} onClick={()=>void sendMagicLink()}>Entrar com link enviado por e-mail</button>}
  {mode==='login'&&<button className="btn neutral full" onClick={()=>{setMode('reset');setPassword('')}}>Ativar conta existente / Esqueci minha senha</button>}
 {error&&<div role="alert" className="notice error">{error}</div>}{notice&&<p role="status">{notice}</p>}
 <p className="muted">Seu cadastro precisa de aprovação antes de acessar as escalas.</p></div></div>
}
