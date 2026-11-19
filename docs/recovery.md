# Completion photo retention and recovery

## Abandoned uploads

Completion uploads are held in the private `herco-completion` Storage bucket. Only unlinked photos that match the app's file path, belong to an existing booking, and are older than the configured retention window are candidates. Linked evidence is excluded. Reservations share a booking lock with completion and prevent a claimed file from becoming evidence during deletion. The cleaner uses the Storage API and records a removal only after the database confirms that Storage metadata is gone.

`wrangler.cleanup.jsonc` defines a separate hourly Worker and ships with `HERCO_PHOTO_CLEANUP_MODE=disabled`. Confirm the project, retention and deployment permissions before enabling it.

| Setting | Where to configure |
| --- | --- |
| `HERCO_PHOTO_CLEANUP_URL` | Cleanup Worker's variables. Use the intended Supabase project HTTPS origin. |
| `HERCO_PHOTO_CLEANUP_SECRET_KEY` | Cleanup Worker's secrets. Use the authorized service credential for the same project. |
| `HERCO_PHOTO_CLEANUP_RETENTION_DAYS` | Cleanup Worker's variables. Set the approved window. The worker and database require at least seven days between upload and cleanup. |
| `HERCO_PHOTO_CLEANUP_MODE` | Keep `disabled` until the migration is installed. Use `report` in staging for a bounded candidate count without reservations or deletion. Use `active` after the retention policy and staging results are approved. |

The worker logs only counts and outcomes. Alert the operator on repeated `claim_failed`, `confirmation_failed` or `retry_pending` results. Outstanding claims become eligible for retry after ten minutes. Keep the database reservation records with the corresponding database backups. [Supabase Storage deletion](https://supabase.com/docs/guides/storage/management/delete-objects)

## Pair database and file backups

The standalone runner `scripts/backup-runner.mjs` pairs a logical PostgreSQL dump with its exact linked photo list. It exports a repeatable-read snapshot, keeps that snapshot open while `pg_dump` runs, encrypts the dump with age, and exports the photos listed by that snapshot. It writes `receipt.json` only after both archives complete and the photo archive passes integrity checks. [PostgreSQL pg_dump snapshot option](https://www.postgresql.org/docs/current/app-pgdump.html)

### Schedule the paired backup

Prepare a private runner with Node, PostgreSQL `psql` and `pg_dump` versions compatible with the source, and the `age` command. Leave `HERCO_BACKUP_MODE=disabled` until the operator has verified a staging backup.

| Runner setting | Value to supply |
| --- | --- |
| `HERCO_BACKUP_DIRECTORY` | Existing private backup storage location outside the repo. |
| `HERCO_BACKUP_AGE_RECIPIENT` | Public age recipient. Hold the corresponding private identity separately for recovery. |
| `PGHOST`, `PGPORT`, `PGDATABASE`, `PGUSER`, `PGSSLMODE`, and a secure password or credential file | Authorized PostgreSQL backup connection for the same Supabase project used by the media reader. Set `PGSSLMODE=verify-full` and supply any required CA configuration. Use a connection that supports a held transaction and imported snapshots. |
| `HERCO_MEDIA_SOURCE_SUPABASE_URL`, `HERCO_MEDIA_SOURCE_SECRET_KEY`, `HERCO_MEDIA_ENCRYPTION_KEY` | Photo read and encryption settings listed below. |
| `HERCO_BACKUP_ALERT_WEBHOOK` | Private HTTPS webhook that accepts a JSON backup-failure summary. Route it to the agreed operator. Also alert on job exit failure or missing receipts in case the webhook is down. |

Sample cron entry, left commented until configured. Use a private service wrapper to load secrets before starting the command.

```text
# 0 19 * * * /path/to/authorized-backup-wrapper node /path/to/Herco/scripts/backup-runner.mjs
```

On Windows, schedule the same Node command through Task Scheduler with the repo as the working directory. Configure the scheduler not to start a second instance if one is still running. The runner sends a redacted failure alert and exits nonzero when a configured backup fails. It does not publish or prune archives.

### Pair an approved managed database backup with media manually

1. Confirm the database plan, backup retention, recovery targets, independent encrypted storage destination, and who owns recovery access. Configure the database backup and Auth restore approach for the actual Supabase project. Database backups contain Storage metadata. Back up the photo bytes separately. [Supabase database backups](https://supabase.com/docs/guides/platform/backups)
2. Record a common recovery point for the database and its files. During a rehearsal, use a source where booking and upload writes are paused while obtaining the paired backups. Record the source project, database backup ID or export, app revision, archive directory, and UTC time.
3. Run the media backup command on a private Node runner with project credentials in its secret store and an existing parent directory outside the repo. Choose a new archive directory for each run. Files and the path manifest are encrypted before writing. The backup command verifies every file's authentication tag and checksum before reporting success.
4. Copy the verified encrypted archive and approved encrypted database backup to independent access-controlled storage. Keep the archive encryption key in a separately controlled vault. Set alerts for missed or failed backups and apply the agreed retention to the archived copies.

```powershell
node scripts/recovery-media.mjs backup 'D:/private-recovery/herco-media-<timestamp>'
node scripts/recovery-media.mjs verify 'D:/private-recovery/herco-media-<timestamp>'
```

The commands are examples. Set `HERCO_MEDIA_ENCRYPTION_KEY` to a randomly generated 32-byte base64 key in the runner secret store. The backup command also uses `HERCO_MEDIA_SOURCE_SUPABASE_URL` and `HERCO_MEDIA_SOURCE_SECRET_KEY`. The script exports photo objects linked to completions. Walk-in forms and signed acknowledgements are database records covered by the paired database backup.

## Rehearse in an isolated project

1. Keep mail, reminders, and photo cleanup disabled on the recovery environment. For paired runner archives, verify the encrypted database checksum against `receipt.json` and use the age recovery identity to inspect the archive with `pg_restore --list`. Have the database administrator review roles, grants, and Supabase-managed schemas before restoring. For managed backups, use the platform's supported project restore. Confirm schema, booking and customer records, trusted memberships, and project-specific Auth settings. Apply the matching app release and migrations as needed. [Supabase restore options](https://supabase.com/docs/guides/platform/backups)
2. Create the private `herco-completion` bucket in that isolated environment. Verify the archive locally. Set `HERCO_MEDIA_TARGET_SUPABASE_URL` and `HERCO_MEDIA_TARGET_SECRET_KEY` for the isolated project, and set `HERCO_MEDIA_RESTORE_ACCEPT=isolated-restore-drill` for the approved run. Supply the original archive encryption key.
3. Run the media restore below. It rejects the source project as a target, checks that the destination database expects exactly the encrypted manifest's paths, uploads with overwrites disabled, and verifies the resulting object bytes. A matching object from an earlier attempt is safe to keep.

```powershell
node scripts/recovery-media.mjs restore 'D:/private-recovery/herco-media-<timestamp>'
```

4. Use fictional and authorized staging identities to check sign-in, staff MFA, booking history, reward and inventory totals, the permission boundaries, and a sample of linked photos. Confirm both an authorized positive test and a denied access test. Record restore timing, the verified recovery point, unresolved differences, and the decision owner. Remove the isolated restore environment only under the approved retention and recovery process.

No active backup schedule, live credential, separate storage destination, recovery target or completed recovery drill is bundled with the code. Those remain launch configuration.
