import {createClient, type SupabaseClient} from '@supabase/supabase-js';
let singleton: SupabaseClient | null = null;
export function getSupabase(){
 if(singleton) return singleton;
 const url=process.env.NEXT_PUBLIC_SUPABASE_URL || "https://dsglwwwwdtjynipauvrp.supabase.co";
 const key=process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY || "sb_publishable_2VsV-MDL1N78X0unw3VM1Q_1Pk0h86a";
 if(!url || !key) throw new Error('Configure NEXT_PUBLIC_SUPABASE_URL e NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY na Vercel.');
 const migrationFetch: typeof fetch = (input, init) => {
  const requestUrl = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url;
  const parsed = new URL(requestUrl);
  const source = new URL(url);
  if(parsed.origin === source.origin && parsed.pathname.startsWith('/rest/v1/')) {
   const target = '/api/migration/data/' + parsed.pathname.slice('/rest/v1/'.length) + parsed.search;
   return fetch(target, init);
  }
  if(parsed.origin === source.origin && ['/auth/v1/signup','/auth/v1/recover','/auth/v1/user'].includes(parsed.pathname) && (init?.method||'GET').toUpperCase() !== 'GET') {
   return Promise.resolve(new Response(JSON.stringify({message:'Alterações de autenticação bloqueadas na homologação.'}),{status:403,headers:{'Content-Type':'application/json'}}));
  }
  return fetch(input, init);
 };
 singleton=createClient(url,key,{...(process.env.NEXT_PUBLIC_DATA_BACKEND==='neon-migration'?{global:{fetch:migrationFetch}}:{}),auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:true}});
 return singleton;
}
