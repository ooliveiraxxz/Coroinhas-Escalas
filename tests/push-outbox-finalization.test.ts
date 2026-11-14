import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const sql=readFileSync(new URL('../migration/sql/091-push-outbox-finalization.sql',import.meta.url),'utf8');
test('finalization distinguishes sent, failed and suppressed without deleting in-app notifications',()=>{
 assert.match(sql,/a\.status='sent'/);
 assert.match(sql,/THEN 'sent'/);
 assert.match(sql,/THEN 'failed'/);
 assert.match(sql,/ELSE 'suppressed'/);
 assert.doesNotMatch(sql,/DELETE\s+FROM\s+public\.notifications/i);
});
test('processing does not finalize sending or retry subscriptions',()=>{
 assert.match(sql,/a\.status NOT IN \('sent','permanent_failure'\)/);
 assert.match(sql,/FOR UPDATE OF o SKIP LOCKED/);
 assert.match(sql,/o\.state='pending'/);
});
test('requires least privilege push role',()=>{
 assert.match(sql,/SECURITY DEFINER SET search_path TO ''/);
 assert.match(sql,/REVOKE ALL ON FUNCTION/);
 assert.match(sql,/TO coroinhas_push_worker/);
});
