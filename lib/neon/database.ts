import {Pool} from 'pg';

let pool:Pool|undefined;

/**
 * Recusa credenciais de proprietário e conexões fora do Postgres remoto.
 * A API só deve acessar o banco usando a conta de serviço limitada.
 */
export function assertMigrationDatabaseUrl(connectionString:string):void {
 let url:URL;
 try{url=new URL(connectionString)}catch{throw new Error('Invalid migration database configuration')}
 if(!['postgres:','postgresql:'].includes(url.protocol)
    ||!(decodeURIComponent(url.username)==='coroinhas_gateway'||(decodeURIComponent(url.username)==='coroinhas_qa_gateway'&&url.hostname==='ep-orange-truth-bel1g9a8.c-9.us-east-2.aws.neon.tech'))
    ||!url.password
    ||!url.hostname.endsWith('.neon.tech')
    ||!url.pathname.endsWith('/coroinhas')){
  throw new Error('Migration requires the restricted coroinhas_gateway database role');
 }
}

export function getPool(){
 const connectionString=process.env.NEON_MIGRATION_DATABASE_URL;
 if(!connectionString)throw new Error('Database unavailable');
 assertMigrationDatabaseUrl(connectionString);
 return pool??=new Pool({
  connectionString,
  max:3,
  idleTimeoutMillis:10000,
  connectionTimeoutMillis:10000
 });
}
