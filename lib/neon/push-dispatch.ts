// Delivery engine independent from the transport and database connection.
// Database functions operate as a least-privilege push role and fail closed.
export type PushClaim={
 notification_id:string;subscription_id:string;endpoint:string;p256dh:string;
 auth:string;title:string;body:string;attempt_number:number
};
export type PushDatabase={
 query:(sql:string,values?:unknown[])=>Promise<{rows:Record<string,unknown>[]}>
};
export type Delivery=(claim:PushClaim)=>Promise<unknown>;

export async function dispatchPushBatch(db:PushDatabase,deliver:Delivery,limit=10){
 if(!Number.isInteger(limit)||limit<1||limit>20)throw new Error('Invalid push batch limit');
 const result=await db.query('SELECT * FROM migration_private.push_claim($1)',[limit]);
 const counts={processed:0,sent:0,failed:0,skipped:0};
 for(const row of result.rows){
  const claim=row as PushClaim;
  counts.processed++;
  const allowed=await db.query('SELECT migration_private.push_eligible($1::uuid,$2::uuid) AS allowed',
   [claim.notification_id,claim.subscription_id]);
  if(allowed.rows[0]?.allowed!==true){
   // Subscription may have been withdrawn, or preferences changed after claim.
   await finish(db,claim,false,410);
   counts.skipped++;continue;
  }
  let failure:unknown;
  try{await deliver(claim)}catch(e){failure=e}
  if(failure===undefined){
   // If acknowledging a successful send fails, keep the original lease.
   // Do not rewrite an already-delivered item as a failed push.
   await finish(db,claim,true,0);
   counts.sent++;
  }else{
   const raw=(typeof failure==='object'&&failure!==null&&'statusCode'in failure)?
    Number(failure.statusCode):0;
   const status=Number.isInteger(raw)&&raw>=100&&raw<=599?raw:0;
   await finish(db,claim,false,status);
   counts.failed++;
  }
 }
 return counts;
}
async function finish(db:PushDatabase,claim:PushClaim,success:boolean,httpStatus:number){
 const result=await db.query(
  'SELECT migration_private.push_finish($1::uuid,$2::uuid,$3::integer,$4::boolean,$5::integer) AS done',
  [claim.notification_id,claim.subscription_id,claim.attempt_number,success,httpStatus]);
 if(result.rows[0]?.done!==true)throw new Error('Delivery lease changed before completion');
}
