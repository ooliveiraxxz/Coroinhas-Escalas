-- Isolated rehearsal ONLY: preserve a superseded update pending final deletion authorization.
-- This DOES NOT delete or hide rows; it makes the conflict auditable and restorable.
DO $guard$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM migration_private.environment WHERE id=true
    AND branch_id='br-odd-bread-bc1jxzsh')
 THEN RAISE EXCEPTION 'Not the clean rehearsal branch'; END IF;
END $guard$;

CREATE TABLE IF NOT EXISTS migration_private.site_update_conflict_archive (
 id uuid PRIMARY KEY,
 snapshot jsonb NOT NULL,
 source_delete_audit_id bigint NOT NULL,
 archived_at timestamptz NOT NULL DEFAULT now(),
 decision text NOT NULL DEFAULT 'pending_review'
   CHECK (decision IN ('pending_review','retain','remove_after_authorization'))
);
REVOKE ALL ON migration_private.site_update_conflict_archive
 FROM PUBLIC,coroinhas_app,coroinhas_gateway,coroinhas_push_worker;

INSERT INTO migration_private.site_update_conflict_archive(id,snapshot,source_delete_audit_id)
SELECT s.id,to_jsonb(s),168 FROM public.site_updates s
WHERE s.id='e1570b88-6c02-4bd7-b9dc-0fcee9c26a87'::uuid
  AND EXISTS(SELECT 1 FROM public.audit_log a
   WHERE a.id=168 AND a.action='DELETE' AND a.table_name='site_updates'
     AND a.record_id=s.id::text)
ON CONFLICT(id) DO NOTHING;
