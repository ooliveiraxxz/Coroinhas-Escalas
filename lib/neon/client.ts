'use client';
import {createClient,type SupabaseClient} from '@supabase/supabase-js';
import {neonAuth} from '@/lib/auth/client';
type Session={user:{id:string;email:string;[key:string]:unknown};access_token:string};
const listeners=new Set<(event:string,session:Session|null)=>void>();
let singleton:SupabaseClient|undefined;
export async function refreshNeonSession(requestedRole?:string){
 const {data,error}=await neonAuth.getSession();
 if(error)throw new Error(error.message||'Não foi possível carregar sua sessão.');
 if(!data?.user){listeners.forEach(fn=>fn('SIGNED_OUT',null));return null;}
 const r=await fetch('/api/migration/session',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({requestedRole})});
 const identity=await r.json();
 if(!r.ok)throw new Error(identity.message||'Não foi possível carregar seu perfil.');
 const session={user:{...data.user,id:identity.profileId},access_token:'cookie-session'};
 listeners.forEach(fn=>fn('SIGNED_IN',session));return session;
}
export function getNeonDatabase(){
 if(singleton)return singleton;
 const client=createClient('https://migration.invalid','unused-public-placeholder',{
  accessToken:async()=> 'cookie-session',
  global:{fetch:(input,init)=>{
   const url=new URL(typeof input==='string'?input:input instanceof URL?input.href:input.url);
   if(!url.pathname.startsWith('/rest/v1/'))throw new Error('Unsupported migration request');
   return fetch('/api/migration/data/'+url.pathname.slice('/rest/v1/'.length)+url.search,{...init,credentials:'same-origin'});
  }}
 });
 const facade={
  getSession:async()=>({data:{session:await refreshNeonSession()},error:null}),
  onAuthStateChange:(fn:(event:string,session:Session|null)=>void)=>{listeners.add(fn);return {data:{subscription:{unsubscribe:()=>listeners.delete(fn)}}}},
  signOut:async()=>{const result=await neonAuth.signOut();if(!result.error)listeners.forEach(fn=>fn('SIGNED_OUT',null));return result},
 };
 singleton=new Proxy(client,{get(target,key){if(key==='auth')return facade;const v=Reflect.get(target,key);return typeof v==='function'?v.bind(target):v}}) as SupabaseClient;
 return singleton;
}
