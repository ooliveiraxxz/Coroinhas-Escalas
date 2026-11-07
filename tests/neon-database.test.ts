import test from 'node:test';
import assert from 'node:assert/strict';
import {assertMigrationDatabaseUrl} from '../lib/neon/database';

test('staging gateway refuses owner and malformed connections',()=>{
 for(const connection of [
  'not-a-database-url',
  'postgresql://coroinhas_owner:secret@ep-test.us-east-1.aws.neon.tech/coroinhas',
  'postgresql://coroinhas_gateway:secret@localhost/coroinhas',
  'postgresql://coroinhas_gateway:secret@ep-test.us-east-1.aws.neon.tech/other',
  'postgresql://coroinhas_gateway@ep-test.us-east-1.aws.neon.tech/coroinhas'
 ]) assert.throws(()=>assertMigrationDatabaseUrl(connection));
});
test('staging gateway accepts restricted database user',()=>{
 assert.doesNotThrow(()=>assertMigrationDatabaseUrl('postgresql://coroinhas_gateway:temporary-example@ep-test.us-east-1.aws.neon.tech/coroinhas?sslmode=require'));
});
