// Offline, isolated, explicitly authorized *test-only* push dispatcher.
// This is NOT a production push worker. It never reads or sends legacy subscriptions.
import pg from 'pg';
import webpush from 'web-push';

const dispatch=process.argv.includes('--send-test');
const url=process.env.NEON_MIGRATION_ADMIN_DATABASE_URL;
if(!url)throw new Error('Private staging maintenance URL required.');
const parsed=new URL(url);
if(!['postgres:','postgresql:'].includes(parsed.protocol)||
   !parsed.hostname.endsWith('.neon.tech')||parsed.pathname!=='/coroinhas'||
   decodeURIComponent(parsed.username)!=='coroinhas_owner')
 throw new Error('Unsafe database connection.');

const allow=(process.env.PUSH_TEST_ALLOWED_SUBSCRIPTIONS||'').split(',').map(x=>x.trim()).filter(Boolean);
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
if(allow.some(x=>!uuid.test(x)))throw new Error('Invalid test subscription allowlist.');
const testNotification=process.env.PUSH_TEST_NOTIFICATION_ID||'';
if(dispatch&&(
 process.env.VERCEL_ENV==='production'||process.env.PUSH_TEST_DISPATCH_APPROVED!=='yes'||
 !uuid.test(testNotification)||allow.length===0||!process.env.PUSH_TEST_VAPID_PUBLIC_KEY||
 !process.env.PUSH_TEST_VAPID_PRIVATE_KEY||!process.env.PUSH_TEST_VAPID_SUBJECT
))throw new Error('Test delivery not explicitly authorized/configured.');

const db=new pg.Client({connectionString:url});
const query=`
SELECT o.notification_id, s.id subscription_id,s.endpoint,s.p256dh,s.auth,
 n.title,n.body
FROM migration_private.push_outbox o
JOIN public.notifications n ON n.id=o.notification_id
JOIN public.profiles p ON p.id=n.user_id
JOIN public.push_subscriptions s ON s.user_id=p.id
WHERE o.state='pending' AND p.approved=true
 AND coalesce(p.notification_preferences->>'enabled','true')<>'false'
 AND s.id=ANY($1::uuid[])
 AND s.created_at >= timestamptz '2026-11-07 00:00:00+00'
 AND ($2::uuid IS NULL OR o.notification_id=$2::uuid)
ORDER BY o.created_at ASC LIMIT 5`;

try{
 await db.connect();
 await db.query('BEGIN READ ONLY');
 const marker=await db.query('SELECT branch_id FROM migration_private.environment WHERE id=true');
 if(marker.rows[0]?.branch_id!=='br-rough-hill-bcj6lzt1')
  throw new Error('Wrong staging branch.');
 const found=await db.query(query,[allow,dispatch?testNotification:null]);
 await db.query('ROLLBACK');
 if(!dispatch){
  // Never expose subscription endpoints, user information or message bodies.
  console.log(JSON.stringify({mode:'dry-run',delivery:false,eligibleTestDeliveries:found.rowCount}));
 }else{
  webpush.setVapidDetails(process.env.PUSH_TEST_VAPID_SUBJECT,process.env.PUSH_TEST_VAPID_PUBLIC_KEY,process.env.PUSH_TEST_VAPID_PRIVATE_KEY);
  let sent=0,failed=0,skipped=0;
  for(const item of found.rows){
   // Claim each subscription/notification pair atomically. Retried sends are
   // at-least-once, but successful claims never repeat; notify SW uses a stable tag.
   await db.query('BEGIN');
   try{
    await db.query(`INSERT INTO migration_private.push_delivery_attempts(notification_id,subscription_id)
                     VALUES($1,$2) ON CONFLICT DO NOTHING`,
                   [item.notification_id,item.subscription_id]);
    const claim=await db.query(`UPDATE migration_private.push_delivery_attempts
      SET status='sending',attempts=attempts+1,
       updated_at=now(),next_attempt_at=now()+interval '15 minutes'
      WHERE notification_id=$1 AND subscription_id=$2 AND attempts<4
        AND (status='pending' OR (status='retry' AND next_attempt_at<=now())
             OR (status='sending' AND updated_at<now()-interval '15 minutes'))
      RETURNING attempts`,[item.notification_id,item.subscription_id]);
    await db.query('COMMIT');
    if(!claim.rowCount){skipped++;continue;}
    try{
     await webpush.sendNotification(
       {endpoint:item.endpoint,keys:{p256dh:item.p256dh,auth:item.auth}},
       JSON.stringify({title:item.title,body:item.body,tag:item.notification_id}),
       {TTL:3600});
     await db.query(`UPDATE migration_private.push_delivery_attempts SET status='sent',updated_at=now(),
                      last_error_code=NULL WHERE notification_id=$1 AND subscription_id=$2`,
                    [item.notification_id,item.subscription_id]);
     sent++;
    }catch(e){
     const status=Number(e?.statusCode)||0;
     const terminal=status===404||status===410||claim.rows[0].attempts>=4;
     const delay=Math.min(60,2**claim.rows[0].attempts);
     await db.query(`UPDATE migration_private.push_delivery_attempts
       SET status=$3,last_error_code=$4,last_error_at=now(),updated_at=now(),
         next_attempt_at=now()+make_interval(mins=>$5)
       WHERE notification_id=$1 AND subscription_id=$2`,
       [item.notification_id,item.subscription_id,terminal?'permanent_failure':'retry',status,delay]);
     failed++;
    }
   }catch{await db.query('ROLLBACK').catch(()=>{});throw new Error('Test push processing failed safely.');}
  }
  console.log(JSON.stringify({mode:'explicit-test',eligible:found.rowCount,sent,failed,skipped}));
 }
}catch{
 await db.query('ROLLBACK').catch(()=>{});
 console.error('Staging push dispatcher did not complete; check privately.');
 process.exitCode=1;
}finally{await db.end().catch(()=>{})}
