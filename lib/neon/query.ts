// Only the app's audited PostgREST subset; all values are parameterized.
import schema from '../../migration/audit/schema.json';
const columns = new Map<string, Set<string>>();
const conflictTargets = new Map<string, Set<string>>();
// Conflict columns must represent a real PK/UNIQUE constraint, never an arbitrary field.
for(const c of schema[0].inventory.constraints){
 if(c.contype!=='p' && c.contype!=='u')continue;
 const match=c.definition.match(/\(([^)]+)\)/);
 if(!match)continue;
 const names=match[1].split(',').map(x=>x.trim().replaceAll('"',''));
 const set=conflictTargets.get(c.table_name)||new Set<string>();
 set.add([...names].sort().join(','));
 conflictTargets.set(c.table_name,set);
}
for (const c of schema[0].inventory.columns) {
 const set = columns.get(c.table_name) || new Set<string>();
 set.add(c.column_name); columns.set(c.table_name, set);
}
const rpcs: Record<string, Record<string, string>> = {
 developer_manage_user:{p_user:'uuid',p_action:'text',p_role:'text'},
 approve_service_request:{p_request_id:'uuid',p_assignment_id:'uuid'},
 delete_notification:{p_group:'uuid'}, developer_usage_summary:{},
 edit_notification:{p_group:'uuid',p_title:'text',p_body:'text'},
 mark_coordinator_message_seen:{p_id:'uuid'}, mark_notification_seen:{p_id:'uuid'},
 reassign_legacy_function:{p_old_assignment_id:'uuid',p_open_assignment_id:'uuid'},
 record_site_access:{p_login:'boolean'},respond_assignment:{p_id:'uuid',p_action:'text',p_reason:'text'},
 send_notification:{p_title:'text',p_body:'text',p_recipient:'uuid'},
};
export class QueryError extends Error {}
const fail = (): never => {throw new QueryError('Operação não suportada no ambiente de migração.');};
export function compileQuery(path:string[],method:string,params:URLSearchParams,body:unknown,prefer='') {
 // Never silently reinterpret duplicate or unsupported PostgREST query parameters.
 const seen=new Set<string>();
 for(const [key] of params){if(seen.has(key))return fail();seen.add(key)}
 if(params.has('columns'))return fail();
 const values: unknown[]=[];
 const value=(v:unknown)=>{values.push(v);return '$'+values.length};
 if(path.length===2&&path[0]==='rpc') {
  const name=path[1],signature=rpcs[name];
  if(!Object.hasOwn(rpcs,name)||method!=='POST'||params.size!==0||!body||Array.isArray(body)||typeof body!=='object')return fail();
  const args=Object.entries(body);
  if(args.some(([k])=>!Object.hasOwn(signature,k)))return fail();
  const text=`SELECT public."${name}"(${args.map(([k,v])=>`"${k}" => ${value(v)}::${signature[k]}`).join(',')}) AS result`;
  return {text,values,rpc:true,returning:true};
 }
 if(path.length!==1||!columns.has(path[0]))return fail();
 const table=path[0],allowed=columns.get(table)!;
 if(params.has('on_conflict') && (method!=='POST' || !prefer.includes('resolution=merge-duplicates')))return fail();
 const col=(c:string)=>{if(!allowed.has(c))return fail();return '"'+c+'"'};
 const selection=params.get('select')||'*';
 const selected=selection==='*'?'*':selection.split(',').map(col).join(',');
 let order='',limit='';const filters:string[]=[];
 for(const [key,raw] of params){
  if(['select','on_conflict'].includes(key))continue;
  if(key==='order'){
   order=' ORDER BY '+raw.split(',').map(item=>{const [c,dir,...rest]=item.split('.');if(rest.length||!['asc','desc'].includes(dir))return fail();return `${col(c)} ${dir.toUpperCase()}`}).join(',');continue;
  }
  if(key==='limit'){if(!/^\d+$/.test(raw)||Number(raw)>1000||Number(raw)<1)return fail();limit=' LIMIT '+value(Number(raw));continue}
  if(raw.startsWith('eq.'))filters.push(`${col(key)} = ${value(raw.slice(3))}`);
  else if(raw==='not.is.null')filters.push(`${col(key)} IS NOT NULL`);
  else if(raw==='is.null')filters.push(`${col(key)} IS NULL`);
  else return fail();
 }
 const where=filters.length?' WHERE '+filters.join(' AND '):'';
 const relation=`public."${method==='GET'&&table==='profiles'?'profile_directory':table}"`;
 const returning=prefer.split(',').some(x=>x.trim()==='return=representation');
 let text:string;
 if(method==='GET')text=`SELECT ${selected} FROM ${relation}${where}${order}${limit||' LIMIT 1000'}`;
 else if(method==='PATCH'){
  if(!filters.length||order||limit||!body||Array.isArray(body)||typeof body!=='object')return fail();
  const entries=Object.entries(body);if(!entries.length||entries.length>30)return fail();
  text=`UPDATE ${relation} SET ${entries.map(([k,v])=>`${col(k)}=${value(v)}`).join(',')}${where}${returning?' RETURNING '+selected:''}`;
 }else if(method==='DELETE'){
  if(!filters.length||order||limit)return fail();
  text=`DELETE FROM ${relation}${where}${returning?' RETURNING '+selected:''}`;
 }else if(method==='POST'){
  if(filters.length||order||limit)return fail();
  const rows=Array.isArray(body)?body:[body];
  if(!rows.length||rows.length>200||rows.some(r=>!r||typeof r!=='object'||Array.isArray(r)))return fail();
  const keys=Object.keys(rows[0]);if(!keys.length||keys.length>30)return fail();
  if(rows.some(r=>Object.keys(r).length!==keys.length||keys.some(k=>!Object.hasOwn(r,k))))return fail();
  text=`INSERT INTO ${relation} (${keys.map(col).join(',')}) VALUES ${rows.map(r=>'('+keys.map(k=>value(r[k])).join(',')+')').join(',')}`;
  if(prefer.includes('resolution=merge-duplicates')){
   const conflict=params.get('on_conflict');if(!conflict)return fail();
   const target=conflict.split(',');target.forEach(col);
   if(new Set(target).size!==target.length || !conflictTargets.get(table)?.has([...target].sort().join(',')))return fail();
   const updates=keys.filter(k=>!target.includes(k));
   text+=` ON CONFLICT (${target.map(col).join(',')}) `+(updates.length?'DO UPDATE SET '+updates.map(k=>`${col(k)}=EXCLUDED.${col(k)}`).join(','):'DO NOTHING');
  }else if(params.has('on_conflict'))return fail();
  if(returning)text+=' RETURNING '+selected;
 }else return fail();
 return {text,values,rpc:false,returning:method==='GET'||returning};
}
