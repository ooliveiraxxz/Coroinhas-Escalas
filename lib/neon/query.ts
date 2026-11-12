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
for (const [table,names] of Object.entries({profiles:['coordination_group'],assignments:['service_group'],requests:['service_group'],service_settings:['key','enabled','updated_at']})) {const set=columns.get(table)||new Set<string>();for(const name of names)set.add(name);columns.set(table,set);}
for (const c of schema[0].inventory.columns) {
 const set = columns.get(c.table_name) || new Set<string>();
 set.add(c.column_name); columns.set(c.table_name, set);
}
const rpcs: Record<string, Record<string, string>> = {
 record_mass_view:{p_mass:'uuid'},
 mass_viewers:{p_mass:'uuid'},
 send_test_notification:{},
 archive_list:{},
 my_site_permissions:{},
 automation_enabled:{p_key:'text'},
 developer_permission_snapshot:{p_user:'uuid'},
 developer_apply_permissions:{p_user:'uuid',p_changes:'jsonb',p_until:'timestamptz',p_confirmation:'text'},
 developer_revoke_permission:{p_id:'uuid',p_confirmation:'text'},
 developer_automation_snapshot:{},
 developer_apply_automations:{p_changes:'jsonb',p_confirmation:'text'},
 developer_list_permission_rules:{},
 developer_save_permission:{p_permission:'text',p_role:'text',p_user:'uuid',p_allowed:'boolean',p_expires:'timestamptz',p_confirmation:'text'},
 developer_set_automation:{p_enabled:'boolean',p_confirmation:'text'},
 has_site_permission:{p_key:'text'},
 request_parent_link:{p_child_email:'text'},
 confirm_parent_link:{p_challenge_id:'uuid',p_code:'text'},
 list_parent_links:{},
 unlink_parent_child:{p_parent:'uuid',p_child:'uuid'},
 developer_manage_user:{p_user:'uuid',p_action:'text',p_role:'text'},
 developer_recent_access:{p_role:'text'},
 developer_audit_recent:{},
 create_mass_with_assignments:{p_title:'text',p_starts_at:'timestamptz',p_location:'text',p_celebrant:'text',p_notes:'text',p_roles:'jsonb'},
 support_create:{p_category:'text',p_message:'text'},
 support_send:{p_ticket:'uuid',p_message:'text'},
 support_close:{p_ticket:'uuid'},
 support_list:{},
 support_messages:{p_ticket:'uuid'},
 support_coord_create:{p_category:'text',p_message:'text'},
 support_coord_list:{},
 support_coord_messages:{p_ticket:'uuid'},
 support_coord_send:{p_ticket:'uuid',p_message:'text'},
 support_coord_close:{p_ticket:'uuid'},
 approve_service_request:{p_request_id:'uuid',p_assignment_id:'uuid'},
 delete_notification:{p_group:'uuid'}, developer_usage_summary:{},
 edit_notification:{p_group:'uuid',p_title:'text',p_body:'text'},
 archive_my_notification:{p_id:'uuid'},
 mark_coordinator_message_seen:{p_id:'uuid'}, mark_notification_seen:{p_id:'uuid'},
 reassign_legacy_function:{p_old_assignment_id:'uuid',p_open_assignment_id:'uuid'},
 record_site_access:{p_login:'boolean'},respond_assignment:{p_id:'uuid',p_action:'text',p_reason:'text'},
 send_notification:{p_title:'text',p_body:'text',p_recipient:'uuid'},
 send_notification_targeted:{p_title:'text',p_body:'text',p_target:'text',p_recipient:'uuid'},
 send_notification_prioritized:{p_title:'text',p_body:'text',p_target:'text',p_recipient:'uuid',p_priority:'boolean',p_priority_until:'timestamptz'},
 poll_create:{p_question:'text',p_options:'jsonb',p_starts_at:'timestamptz',p_ends_at:'timestamptz',p_multiple:'boolean',p_priority:'boolean'},
 poll_list:{},
 poll_tick:{},
 poll_vote:{p_poll:'uuid',p_options:'uuid[]'},
 poll_change_vote:{p_poll:'uuid',p_options:'uuid[]'},
 poll_update:{p_poll:'uuid',p_question:'text',p_options:'jsonb',p_starts_at:'timestamptz',p_ends_at:'timestamptz',p_multiple:'boolean',p_priority:'boolean'},
};
export class QueryError extends Error {}
const fail = (): never => {throw new QueryError('Operação não suportada no ambiente de migração.');};
export function compileQuery(path:string[],method:string,params:URLSearchParams,body:unknown,prefer='') {
 // Never silently reinterpret duplicate or unsupported PostgREST query parameters.
 const seen=new Set<string>();
 for(const [key] of params){if(seen.has(key))return fail();seen.add(key)}
 if(params.has('columns') && method!=='POST')return fail();
 const values: unknown[]=[];
 const value=(v:unknown)=>{values.push(v);return '$'+values.length};
 if(path.length===2&&path[0]==='rpc') {
  const name=path[1],signature=rpcs[name];
  if(!Object.hasOwn(rpcs,name)||method!=='POST'||params.size!==0||!body||Array.isArray(body)||typeof body!=='object')return fail();
  const args=Object.entries(body);
  if(args.some(([k])=>!Object.hasOwn(signature,k)))return fail();
  if(name==='list_parent_links')return {text:`SELECT COALESCE(json_agg(t),'[]'::json) AS result FROM public.list_parent_links() t`,values:[],rpc:true,returning:true};
  const text=`SELECT public."${name}"(${args.map(([k,v])=>`"${k}" => ${value(signature[k]==='jsonb'?JSON.stringify(v):v)}::${signature[k]}`).join(',')}) AS result`;
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
  if(['select','on_conflict','columns'].includes(key))continue;
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
  if(params.has('columns')){
   const supplied=params.get('columns')!.split(',').map(k=>k.trim().replace(/^"|"$/g,''));
   if(supplied.length!==keys.length||new Set(supplied).size!==keys.length||supplied.some(k=>!keys.includes(k)))return fail();
  }
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
