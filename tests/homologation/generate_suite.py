import json
from pathlib import Path

# Runs only in the disposable schema-only homologation project.
uid=lambda i: f'00000000-0000-4000-8000-{i:012}'
def actor(i):
    return f"EXECUTE 'RESET ROLE'; PERFORM set_config('app.user_id','{uid(i)}',true); EXECUTE 'SET LOCAL ROLE coroinhas_app';"
def owner(): return "EXECUTE 'RESET ROLE';"
def check(expr): return f"IF NOT coalesce(({expr}),false) THEN RAISE EXCEPTION 'assertion failed'; END IF;"
cases=[]
def add(name,body): cases.append((name,body))
def deny(sql):
    return "denied:=false; BEGIN "+sql+" EXCEPTION WHEN insufficient_privilege THEN denied:=true; END; "+check('denied')

schema={'catalogs':json.loads(Path(__file__).with_name('catalog.json').read_text())}
for row in schema['catalogs']['permission_catalog']:
    key=row['key']
    for allowed in (True,False):
        b=str(allowed).lower()
        add(f'permission/{key}/{b}',owner()+f"DELETE FROM public.permission_rules WHERE subject_user='{uid(2)}';"+actor(1)+f"PERFORM public.developer_apply_permissions('{uid(2)}','[{{\"key\":\"{key}\",\"allowed\":{b}}}]',NULL,'DESENVOLVEDOR');"+actor(2)+check(f"public.has_site_permission('{key}')={b}"))
    default='coroinha' in row['default_roles']
    add(f'permission/{key}/expiry',owner()+f"DELETE FROM public.permission_rules WHERE subject_user='{uid(2)}';"+actor(1)+f"PERFORM public.developer_apply_permissions('{uid(2)}','[{{\"key\":\"{key}\",\"allowed\":{str(not default).lower()}}}]',now()+interval '1 hour','DESENVOLVEDOR');"+owner()+f"UPDATE public.permission_rules SET expires_at=now()-interval '1 second' WHERE subject_user='{uid(2)}';"+actor(2)+check(f"public.has_site_permission('{key}')={str(default).lower()}"))
for row in schema['catalogs']['automation_catalog']:
    key=row['key']
    add(f'automation/{key}/switch',actor(1)+f"PERFORM public.developer_apply_automations('[{{\"key\":\"{key}\",\"enabled\":false}}]','DESENVOLVEDOR');"+check(f"NOT public.automation_enabled('{key}')")+f"PERFORM public.developer_apply_automations('[{{\"key\":\"{key}\",\"enabled\":true}}]','DESENVOLVEDOR');"+check(f"public.automation_enabled('{key}')"))
add('permission/common-user-cannot-grant',actor(2)+deny(f"PERFORM public.developer_apply_permissions('{uid(2)}','[{{\"key\":\"manage_users\",\"allowed\":true}}]',NULL,'DESENVOLVEDOR');"))
add('permission/confirmation-required',actor(1)+deny(f"PERFORM public.developer_apply_permissions('{uid(2)}','[{{\"key\":\"manage_users\",\"allowed\":true}}]',NULL,'');"))
add('permission/early-revocation',actor(1)+f"PERFORM public.developer_apply_permissions('{uid(2)}','[{{\"key\":\"manage_users\",\"allowed\":true}}]',now()+interval '1 hour','DESENVOLVEDOR');"+owner()+f"SELECT id INTO record_id FROM public.permission_rules WHERE subject_user='{uid(2)}' AND permission_key='manage_users' LIMIT 1;"+actor(1)+"PERFORM public.developer_revoke_permission(record_id,'DESENVOLVEDOR');"+actor(2)+check("NOT public.has_site_permission('manage_users')"))
for i in (2,3,4,5,6,7,8):
    add(f'archives/default-denial/{i}',actor(i)+deny('PERFORM public.archive_list();'))
add('archives/developer-access',actor(1)+"PERFORM public.archive_list();")
for i in (2,3,6):
    add(f'support/developer-channel/{i}',actor(i)+"result:=public.support_create('Dúvida','QA isolated support'); record_id:=(result->>'id')::uuid; PERFORM public.support_send(record_id,'Follow-up');"+actor(1)+"PERFORM public.support_send(record_id,'Answer'); PERFORM public.support_close(record_id);"+owner()+check("(SELECT status='encerrado' FROM public.support_tickets WHERE id=record_id)"))
add('support/pending-user-blocked',actor(7)+deny("PERFORM public.support_create('Dúvida','QA denied');"))
add('support/ceremonial-coordinator-create',actor(3)+"PERFORM public.support_coord_create('Dúvida','Ceremonial request');")
add('support/cross-group-list-denied',actor(5)+check("jsonb_array_length(public.support_coord_list())=0"))
for action,args in [('messages','record_id'),('send',"record_id,'Unauthorized answer'"),('close','record_id')]:
    add(f'support/cross-group-{action}-denied',owner()+"SELECT id INTO record_id FROM public.support_tickets WHERE target_role='coordenadora' LIMIT 1;"+actor(5)+deny(f'PERFORM public.support_coord_{action}({args});'))
add('support/matching-coordinator-reply',owner()+"SELECT id INTO record_id FROM public.support_tickets WHERE target_role='coordenadora' LIMIT 1;"+actor(4)+"PERFORM public.support_coord_messages(record_id); PERFORM public.support_coord_send(record_id,'Authorized answer'); PERFORM public.support_coord_close(record_id);")

header="""DO $suite$
DECLARE denied boolean; record_id uuid; result jsonb; results jsonb:='[]'; state text; detail text;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM migration_private.environment WHERE branch_id='br-crimson-mud-bcyk3t3x') THEN RAISE EXCEPTION 'Isolated branch required'; END IF;
"""
blocks=[]
for name,body in cases:
    blocks.append("BEGIN "+body+" RAISE EXCEPTION 'QA_ROLLBACK_OK'; EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS state=RETURNED_SQLSTATE,detail=MESSAGE_TEXT; EXECUTE 'RESET ROLE'; results:=results||jsonb_build_array(jsonb_build_object('name','"+name+"','passed',detail='QA_ROLLBACK_OK','error',CASE WHEN detail='QA_ROLLBACK_OK' THEN NULL ELSE state||': '||detail END)); END;")
sql=header+'\n'.join(blocks)+"\nINSERT INTO qa_results VALUES(results); END $suite$;"
Path('/tmp/qa-suite.json').write_text(json.dumps(['CREATE TEMP TABLE qa_results(result jsonb);',sql,'SELECT result FROM qa_results;']))
if __name__=='__main__': print(len(cases))
