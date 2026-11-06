import {Pool} from 'pg';
let pool:Pool|undefined;
export function getPool(){
 if(!process.env.NEON_MIGRATION_DATABASE_URL)throw new Error('Database unavailable');
 return pool??=new Pool({connectionString:process.env.NEON_MIGRATION_DATABASE_URL,max:3,idleTimeoutMillis:10000,connectionTimeoutMillis:10000});
}
