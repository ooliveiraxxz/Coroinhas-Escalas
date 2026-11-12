'use client';
import {useState} from 'react';
import {Church,Eye,EyeOff,MessageCircle} from 'lucide-react';
import {neonAuth} from '@/lib/auth/client';
import {refreshNeonSession} from '@/lib/neon/client';
export default function NeonLogin(){
 const [mode,setMode]=useState<'login'|'signup'|'reset'|'reset-code'>('login');
 const [email,setEmail]=useState(''),[name,setName]=useState(''),[password,setPassword]=useState(''),[otp,setOtp]=useState(''),[role,setRole]=useState('coroinha'),[busy,setBusy]=useState(false),[error,setError]=useState(''),[visible,setVisible]=useState(false),[notice,setNotice]=useState('');
 async function recordLogin(){
  try{
   const response=await fetch('/api/migration/data/rpc/record_site_access',{method:'POST',headers:{'Content-Type':'application/json'},credentials:'same-origin',body:JSON.stringify({p_login:true})});
   if(!response.ok)console.warn('Histórico de login indisponível.');
  }catch{console.warn('Histórico de login indisponível.');}
 }
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
    await refreshNeonSession(role);await recordLogin();return;
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
   await refreshNeonSession(role);await recordLogin();
  }catch(e){setError(e instanceof Error?e.message:'Não foi possível concluir.')}finally{setBusy(false)}
 }
 const title={login:'Entrar',signup:'Criar conta',reset:'Esqueci minha senha','reset-code':'Definir senha'}[mode];
 return <div className="auth auth-login">
  <header className="auth-brand">
   <div className="brand-symbol"><Church size={38} strokeWidth={1.6}/></div>
   <h1>Coroinhas</h1>
   <p>Servir é amar.</p>
  </header>
  <section className="auth-box auth-login-card" aria-label={title}>
   <h2>{title}</h2>
   {mode==='reset'&&<p className="auth-help">Informe seu e-mail para receber um código de recuperação.</p>}
   {mode==='reset-code'&&<p className="auth-help">Digite o código enviado ao seu e-mail e escolha uma nova senha.</p>}
   <form onSubmit={e=>{e.preventDefault();void submit()}}>
    {mode==='signup'&&<>
     <label className="field">Nome completo<input required autoComplete="name" value={name} onChange={e=>setName(e.target.value)}/></label>
     <label className="field">Tipo de cadastro<select value={role} onChange={e=>setRole(e.target.value)}><option value="coroinha">Sou coroinha</option><option value="cerimoniario">Sou cerimoniário</option><option value="pai">Sou pai, mãe ou responsável</option></select></label>
    </>}
    <label className="field">E-mail<input required type="email" autoComplete="email" value={email} onChange={e=>setEmail(e.target.value)}/></label>
    {mode==='reset-code'&&<label className="field">Código recebido<input required inputMode="numeric" autoComplete="one-time-code" value={otp} onChange={e=>setOtp(e.target.value)}/></label>}
    {mode!=='reset'&&<label className="field">{mode==='reset-code'?'Nova senha':'Senha'}
     <div className="password-field"><input required minLength={8} type={visible?'text':'password'} autoComplete={mode==='login'?'current-password':'new-password'} value={password} onChange={e=>setPassword(e.target.value)}/><button type="button" className="password-toggle" aria-label={visible?'Ocultar senha':'Mostrar senha'} onClick={()=>setVisible(!visible)}>{visible?<EyeOff size={21}/>:<Eye size={21}/>}</button></div>
    </label>}
    {mode==='login'&&<div className="auth-forgot-row"><button type="button" className="auth-forgot-link" onClick={()=>{setMode('reset');setError('');setNotice('');setPassword('')}}>Esqueci minha senha</button></div>}
    <button type="submit" className="btn full auth-primary" disabled={busy}>{busy?'Aguarde…':mode==='reset'?'Enviar código':mode==='reset-code'?'Redefinir senha':title}</button>
   </form>
   {mode==='login'&&<div className="auth-secondary"><span>Ainda não tem uma conta?</span><button type="button" className="btn alt full" disabled={busy} onClick={()=>{setMode('signup');setError('');setNotice('')}}>Criar conta / Solicitar acesso</button></div>}
   {mode!=='login'&&<button type="button" className="auth-back-link" disabled={busy} onClick={()=>{setMode('login');setError('');setNotice('');setOtp('')}}>Voltar para entrar</button>}
   {error&&<div role="alert" className="notice error">{error}</div>}
   {notice&&<p role="status" className="auth-help">{notice}</p>}
   {mode==='signup'&&<p className="auth-approval-note">Seu cadastro será analisado pela coordenação antes da liberação.</p>}
  </section>
  <a className="auth-quick-support" style={{display:'flex',alignItems:'center',justifyContent:'center',gap:10,backgroundColor:'#ffffff',color:'#741d33',border:'1px solid #ead7dc',borderRadius:14,marginTop:32,padding:'13px 20px',minHeight:52,width:'min(100%, 430px)',fontSize:16,fontWeight:750,textDecoration:'none',boxShadow:'0 8px 24px rgba(30,0,10,.18)'}} href={"https://wa.me/5511915988001?text=Ol%C3%A1!%20Vim%20atrav%C3%A9s%20do%20aplicativo%20Escalas%20de%20Coroinhas%20e%20n%C3%A3o%20estou%20conseguindo%20efetuar%20login.%20Poderia%20me%20ajudar%2C%20por%20favor%3F"} target="_blank" rel="noopener noreferrer" aria-label="Suporte pelo WhatsApp para problemas de login">
   <MessageCircle size={20} strokeWidth={2.2} aria-hidden="true"/><span>Suporte</span>
  </a>
 </div>;
}
