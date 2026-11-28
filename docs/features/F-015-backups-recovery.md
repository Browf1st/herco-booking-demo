# F-015: Backups, photo cleanup and restore drill
> Documented from existing docs on 2026-11-20 — owner to confirm.

**Status:** Blocked (storage, schedule and recovery targets not chosen) · **Milestone:** M3 · **Depends on:** F-009

## In one sentence
The shop's database and completion photos are backed up together, abandoned uploads are cleaned up, and a restore is practised, so data can be recovered after a mistake or outage.

## User steps (exactly how it works)
1. An operator sets up a private backup runner (Node, `psql`/`pg_dump`, `age`) with secrets in its own store.
2. The runner makes a paired, encrypted database dump plus linked photo archive and writes `receipt.json` when both pass checks.
3. Copies go to independent encrypted storage; failures alert the operator by webhook.
4. A separate hourly cleanup Worker removes old unlinked photo uploads (mode: disabled → report → active).
5. In an isolated project, the operator restores database and photos and checks sign-in, history, totals, permissions and sample photos.

## Rules and details
- Mail, reminders and cleanup stay disabled on the restore environment.
- Cleanup never touches linked evidence; minimum 7 days between upload and cleanup.
- Media restore refuses the source project as target and needs `HERCO_MEDIA_RESTORE_ACCEPT=isolated-restore-drill`.
- Walk-in forms and signatures are covered by the database backup.
- Schedule, retention, acceptable data loss and downtime, storage destination, recovery owner: TBD — ask owner (Q-16).
- Recovery doc step 4 mentions "staff MFA"; current policy is password-only (Q-19).

## Screens
- None (operator scripts and Workers).

## Data
- Upload reservation records; backup receipts outside the repo.

## API
- None public.

## Edge cases and errors
- Webhook down → also alert on non-zero exit or missing receipt.
- Repeated `claim_failed`, `confirmation_failed`, `retry_pending` → alert operator.
- Second backup instance starting while one runs → scheduler must prevent it.

## Must not break
- Linked completion evidence (F-009).

## Acceptance tests (all must pass)
- [ ] Production backup produces a verified receipt and encrypted archives; recovery is checked on a disposable isolated target without a standing staging deployment.
- [ ] Cleanup in report mode lists only unlinked, old uploads. (2026-11-20: run once locally against the dev project in report mode with a 30-day placeholder retention; it returned 0 candidates and deleted nothing. Still to prove with a real old unlinked upload.)

## Local setup status (2026-11-20)
- Cleanup settings live in the gitignored `.dev.vars.cleanup`: dev project URL, its secret key, `HERCO_PHOTO_CLEANUP_MODE=report`, `HERCO_PHOTO_CLEANUP_RETENTION_DAYS=30` (placeholder until Q-03 is answered).
- `wrangler.cleanup.jsonc` still ships `disabled`. No cleanup Worker is deployed. Switching to `active` waits for the retention answer (Q-03) and a separately authorized read-only report against the intended production project.
- [ ] Isolated restore drill passes; timing and recovery point recorded.

## Production proof and backup reminder — 2026-11-27

- Owner uses **one production application environment**. Do not require a standing staging deployment. Verification uses local fictional fixtures and an isolated disposable restore target; never reset/restore over production merely to test recovery.
- Back up production database, Auth/recovery requirements, private photo bytes and booking-proof metadata together. Include proof saved while Booked as well as Completed, not just finalized completion rows. Preserve historical price/service snapshots and staff grants.
- Encrypt backups, restrict access, retain an independent copy, verify receipts/freshness and rehearse recovery. A database dump alone does not prove photos are backed up; record what Auth/storage/provider configuration requires separate recovery.
- Failed/stale backups and failed recovery checks must alert **elijahpayoc12@gmail.com** through F-027's independent alert path. Successful HTTP response alone does not prove a successful restore.
- Schedule, retention, independent storage, acceptable data loss/downtime and recovery owner remain decisions to settle. Linked Booked/Completed proof is never treated as abandoned upload merely because status is not Completed. Retention/deletion is not authorized by this reminder.

## Ready checklist (no code until all are ticked and the owner approves)
- [x] Every user step is written out
- [ ] Rules, limits and permissions are decided
- [x] Screens and their states are described
- [x] Data and API are designed
- [x] Edge cases and "must not break" are listed
- [x] Acceptance tests are written
- [ ] No open questions left
- [ ] **Owner approved:**
