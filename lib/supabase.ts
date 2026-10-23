import {createClient, type SupabaseClient} from '@supabase/supabase-js';
let singleton: SupabaseClient | null = null;
export function getSupabase(){
 if(singleton) return singleton;
 const url=process.env.NEXT_PUBLIC_SUPABASE_URL || "https://dsglwwwwdtjynipauvrp.supabase.co";
 const key=process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY || "sb_publishable_2VsV-MDL1N78X0unw3VM1Q_1Pk0h86a";
 if(!url || !key) throw new Error('Configure NEXT_PUBLIC_SUPABASE_URL e NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY na Vercel.');
 singleton=createClient(url,key,{auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:true}});
 return singleton;
}
