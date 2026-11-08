-- Read-only logical reconciliation of the one source-deleted update.
-- Only run against the isolated clean rehearsal branch. NO DELETE or mutation.
-- The matching Supabase audit entry was independently verified from the source.
WITH marker AS (
 SELECT EXISTS(SELECT 1 FROM migration_private.environment
  WHERE id=true AND branch_id='br-odd-bread-bc1jxzsh') AS correct_branch
), archived AS (
 SELECT a.id,a.source_delete_audit_id,a.decision,
        a.snapshot=to_jsonb(u) AS archive_matches_live,
        EXISTS(SELECT 1 FROM public.audit_log l
          WHERE l.id=a.source_delete_audit_id AND l.action='DELETE'
            AND l.table_name='site_updates' AND l.record_id=a.id::text)
         AS has_delete_audit
 FROM migration_private.site_update_conflict_archive a
 JOIN public.site_updates u ON u.id=a.id
), eligible AS (
 SELECT id FROM archived
 WHERE decision='pending_review' AND archive_matches_live AND has_delete_audit
)
SELECT
 (SELECT correct_branch FROM marker) AS correct_branch,
 (SELECT count(*)::int FROM archived) AS archived_conflicts,
 (SELECT count(*)::int FROM eligible) AS verified_tombstones,
 (SELECT count(*)::int FROM public.site_updates) AS physical_updates,
 (SELECT count(*)::int FROM public.site_updates u
  WHERE NOT EXISTS(SELECT 1 FROM eligible e WHERE e.id=u.id)) AS logical_updates,
 (SELECT md5(coalesce(string_agg(to_jsonb(u)::text,E'\n'
  ORDER BY to_jsonb(u)::text),''))
  FROM public.site_updates u
  WHERE NOT EXISTS(SELECT 1 FROM eligible e WHERE e.id=u.id)) AS logical_checksum,
 (SELECT correct_branch FROM marker)
  AND (SELECT count(*) FROM archived)=1
  AND (SELECT count(*) FROM eligible)=1 AS archived_deletion_verified;
