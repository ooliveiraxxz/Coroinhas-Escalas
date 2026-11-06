import test from 'node:test';
import assert from 'node:assert/strict';
import {NextRequest} from 'next/server';
import {GET} from '../app/api/migration/data/[...path]/route';
const req=()=>new NextRequest('http://localhost/api/migration/data/profiles');
const context={params:Promise.resolve({path:['profiles']})};
test('migration endpoint defaults to disabled and cannot be enabled in production',async()=>{
 delete process.env.NEON_MIGRATION_ENABLED;
 assert.equal((await GET(req(),context)).status,404);
 process.env.NEON_MIGRATION_ENABLED='true';process.env.VERCEL_ENV='production';
 assert.equal((await GET(req(),context)).status,404);
 delete process.env.VERCEL_ENV;delete process.env.NEON_MIGRATION_ENABLED;
});
test('missing environment and missing token fail before any database connection',async()=>{
 process.env.NEON_MIGRATION_ENABLED='true';
 assert.equal((await GET(req(),context)).status,503);
 process.env.NEON_MIGRATION_DATABASE_URL='postgres://invalid.example/test';
 process.env.NEXT_PUBLIC_SUPABASE_URL='https://example.invalid';
 process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY='test';
 assert.equal((await GET(req(),context)).status,401);
 for(const k of ['NEON_MIGRATION_ENABLED','NEON_MIGRATION_DATABASE_URL','NEXT_PUBLIC_SUPABASE_URL','NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY'])delete process.env[k];
});
