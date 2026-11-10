# Isolated homologation, 2026-11-10

Source: production commit `5a0f1ae`, with the label/test corrections from `bab9c86`.
Target: Neon project `rough-tree-68971996`, branch `br-crimson-mud-bcyk3t3x`, database `coroinhas`.
Production has not received migrations 054–056.

The target contains schema-only copies of 32 application tables, 79 functions, 36 RLS policies and the permission/automation catalogs. No production account, schedule, message, subscription, credential or backup was copied. Neon Auth was provisioned independently. The resolver's branch guard was changed only in homologation to match its actual branch. Function EXECUTE grants were reconciled with the source after an initially over-restrictive copy produced false failures.

`generate_suite.py` builds 105 SQL/RPC checks; `generate_flows.py` builds 22 workflow/date checks. They write SQL transaction arrays to `/tmp/qa-suite.json` and `/tmp/qa-flows.json`. Each case rolls back its changes. Run only with the target's eight fictitious profiles and the coroinha support-ticket fixture. These are server tests, not browser E2E tests. `archive_privacy.sql` covers three archive-recipient isolation checks.

Verified fixes:
- Ceremonial members can open coordinator support.
- Other-group coordinators cannot list/read/reply/close support tickets.
- Withdrawal notices respect the service group and automation switch.
- Ceremonial members have the default poll-voting permission; explicit overrides remain effective.
- Archive permission no longer exposes individual announcements addressed to other users.

Native Auth lifecycle checks used only `qa-delete@example.invalid`: delete removed Auth/profile without banning; the email was successfully recreated; ban removed the recreated account; recreation through the Auth tool was refused. A direct uppercase-email insertion was also rejected by the database trigger.

Outstanding release blockers:
- Authenticated browser journeys for all eight scenarios, including mobile layouts, downloads and real-device push.
- Production has no `NEON_PUSH_DISPATCH_ENABLED`, `NEON_PUSH_DATABASE_URL`, `NEXT_PUBLIC_VAPID_PUBLIC_KEY` or `VAPID_SUBJECT` in the inspected Vercel configuration; native push delivery is not approved.
- The single daily cron does not guarantee the three-hour automatic approval window while everyone is offline.
- Full per-button E2E inventory remains incomplete; SQL success is not a release approval.

Existing 53 automated tests and six public browser checks were not rerun unnecessarily. The production deployment remained READY at `5a0f1ae` during this continuation.
