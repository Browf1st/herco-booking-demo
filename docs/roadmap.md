# Roadmap: HERCO booking
<!-- Source of truth for progress. One line per feature; details live in docs/features/. Only the main session edits this file. -->

**Vision:** An online booking and shop-operations app for HERCO, a Philippine motorcycle ceramic and powder-coating shop. Customers book and track their work, and staff run the schedule, walk-ins, completions, points, inventory and reports.
**Updated:** 2026-11-20 · **Visual page:** none yet
**Built from:** AGENTS.md, requirements-coverage.md, production-plan.md, production-handoff.md, walk-in-intake.md, staff-access.md, email-worker.md, recovery.md. Owner to confirm every line.

## Status key
Idea → Needs answers → Ready (spec approved) → Building → Testing → Done · Blocked (say why)
"Testing" here means: built in the Worker app and checked locally, but not yet proven on a live staging setup.

## Milestones

### M1: Static demo on GitHub Pages: Done
Every feature below exists in demo form, with browser storage and pretend sign-in. The demo stays online during staging and is the visual reference (see docs/ui-parity-audit.md).

### M2: Production backend (Supabase + Cloudflare Worker)
| ID | Feature | Status | Depends on | Spec |
|---|---|---|---|---|
| F-001 | Customer booking with live price estimate | Testing | F-002, F-003, F-005 | [spec](features/F-001-customer-booking.md) |
| F-002 | Availability, date overrides and slot blocks | Needs answers (Q-07) | F-012 | [spec](features/F-002-availability.md) |
| F-003 | Coating catalog, pricing rules and promotions | Blocked: approved price list not supplied (Q-05, Q-06) | F-012 | [spec](features/F-003-catalog-pricing.md) |
| F-004 | Service change and promotion history | Testing | F-001, F-003 | [spec](features/F-004-service-history.md) |
| F-005 | Customer account and sign-in | Testing (Google/Facebook blocked on provider apps) | none | [spec](features/F-005-account-sign-in.md) |
| F-006 | My Bookings and change requests | Needs answers (Q-08, Q-12) | F-001, F-005 | [spec](features/F-006-my-bookings.md) |
| F-007 | Staff booking queue, calendar and booking history | Testing | F-002, F-012 | [spec](features/F-007-staff-queue.md) |
| F-008 | Manual booking, walk-in and intake form | Blocked: approved form text and signature method (Q-01, Q-02) | F-005, F-012 | [spec](features/F-008-manual-walk-in-intake.md) |
| F-009 | Completion with photos and exact prices | Blocked: private photo bucket and retention not set up (Q-03) | F-003, F-007 | [spec](features/F-009-completion-photos.md) |
| F-010 | HERCO Points and rewards | Needs answers (Q-14) | F-005, F-012 | [spec](features/F-010-points-rewards.md) |
| F-011 | Reports and activity log | Needs answers (Q-04) | F-009, F-012 | [spec](features/F-011-reports-activity-log.md) |
| F-012 | Staff access and roles | Needs answers (Q-11); first Owner set up | F-005 | [spec](features/F-012-staff-access.md) |
| F-013 | Inventory and stock exports | Testing (opening counts needed, Q-15) | F-012 | [spec](features/F-013-inventory.md) |
| F-014 | Email notifications (Brevo worker) | Blocked: email worker not configured (Q-13) | F-001, F-006 | [spec](features/F-014-email-notifications.md) |

UI parity: the Worker screens are being matched to the demo look. Open items in docs/ui-parity-audit.md (Q-18).

### M3: Release and operations
| ID | Feature | Status | Depends on | Spec |
|---|---|---|---|---|
| F-015 | Backups, photo cleanup and restore drill | Blocked: storage, schedule and recovery targets not chosen (Q-16) | F-009 | [spec](features/F-015-backups-recovery.md) |
| F-016 | Staging hardening, monitoring, analytics and production release | Blocked: hosting, domain, alerts and owners not confirmed (Q-17) | all M2 | [spec](features/F-016-release-monitoring.md) |

## Questions waiting for you
- [ ] Q-01 F-008: How do customers sign the walk-in form? (A) typed full name plus a tick box, already built (B) drawn signature, needs new work. Example: "Juan Dela Cruz" typed under the form.
- [ ] Q-02 F-008: Please supply the final form title, full text, version name and who approves it.
- [ ] Q-03 F-008/F-009: How long do we keep completion photos and signed forms, and who can see them? (A) staff only, kept 1 year (B) customer can also see photos (C) other. Unlinked uploads are deleted after (A) 7 days, the minimum (B) 30 days.
- [ ] Q-04 F-011: Do you need "collected revenue" (money actually received) in reports? (A) no, show only "Completed service value" (B) yes, then name the source, e.g. a cash book, and the rules for discounts and refunds.
- [ ] Q-05 F-003: Please supply the approved catalog: service names, fixed prices or ranges, which need a shop quote, exact bike models, finishes, parts and wheel sizes.
- [ ] Q-06 F-003: Promotions: (A) one active promotion at a time, as built (B) several at once. Which promotions run first?
- [ ] Q-07 F-002: How many bikes per time slot, how long does each service take, and what are the regular opening hours? Example: 2 bikes per hour, ceramic takes 3 hours, open 9am–6pm.
- [ ] Q-08 F-006: Limits on changes: (A) customers can cancel or reschedule anytime, staff decide (B) not within 24 hours of the visit. Do open requests expire? Does the old time stay held while a reschedule waits?
- [ ] Q-09 F-001: Guest booking without an account: (A) keep off, sign-in required, as built (B) allow guests, with rules for claiming the booking later.
- [ ] Q-10 F-008: Manual bookings for customers with no account: (A) staff can only book for verified accounts, as built (B) staff can create a booking and link it later.
- [ ] Q-11 F-012: Confirm the role list and the pages and actions each role gets: Owner, Superadmin, Admin, restricted Admin, Staff. Who is the Superadmin?
- [ ] Q-12 F-006/F-007: Can customers see the shop's approval notes? (A) no, staff only (B) yes, a separate customer-facing note.
- [ ] Q-13 F-014: Approve email templates, which events send email, the shop inbox for change requests, and the reminder timing: (A) off (B) e.g. 24 hours before.
- [ ] Q-14 F-010: Points are awarded (A) by hand, as the handoff says (B) automatically on completion, as the plan suggests. What are the point values, rewards and any expiry?
- [ ] Q-15 F-013: Opening stock counts, and do you have real records to import? Can stock go below zero? (A) no, refuse (B) yes, flag it. Do you want low-stock alerts?
- [ ] Q-16 F-015: Backup schedule and how long to keep backups; how much data loss and downtime are acceptable (e.g. 1 day, 4 hours); who runs a restore.
- [ ] Q-17 F-016: Confirm Cloudflare Workers as host, budget, expected traffic, production domain, alert recipients, GA4 property and consent wording, and release and rollback owners.
- [ ] Q-18 UI parity: decide the open items in docs/ui-parity-audit.md: navigation grouping, pop-up (modal) behavior, and customer-visible or data differences from the demo.
- [ ] Q-19 Staff MFA: the 2026-11-20 policy says password-only for staff, but walk-in-intake.md and recovery.md still mention an authenticator. Confirm password-only applies everywhere.
- [ ] Q-20 Is the hosted Supabase project already in use your staging project, or a dev project? A separate production project is still needed.
- [ ] Q-21 F-004: Old bookings without an original price snapshot: (A) show "price history not available" (B) hide the history section.
- [ ] Q-22 F-005: If someone signs in with Google using an email that already has a password account: (A) link them automatically after email check (B) keep separate. Also: how many failed sign-ins before a pause (e.g. 5 in 15 minutes)?
- [ ] Q-23 F-011: Do you need report downloads (CSV)? If yes, which figures, and who may download them?

## Needs you (accounts, keys, content)
Enter secret values only in the provider's settings or ignored local files, never in chat or Git.
- [ ] Isolated Supabase staging project (and later a separate production project), with migration and Auth/Storage access for the maintainer. Values: `PUBLIC_SUPABASE_URL`, `PUBLIC_SUPABASE_PUBLISHABLE_KEY`.
- [ ] Cloudflare account and billing owner, staging hostname, production domain and DNS owner. Values: `APP_ORIGIN`, `APP_ENV`.
- [ ] Private Storage bucket `herco-completion` (JPEG/PNG/WebP, 4 MB) and `HERCO_STORAGE_SECRET_KEY` in the site Worker secrets.
- [ ] Brevo: API key, SMTP login for Supabase Auth, verified sender and domain DNS, reply-to inbox, test recipients. Values: `BREVO_API_KEY`, `EMAIL_FROM`, `EMAIL_REPLY_TO`, `STAGING_EMAIL_ALLOWLIST`; turn on `HERCO_AUTH_EMAIL_ENABLED` after staging check.
- [ ] Email worker settings: `HERCO_EMAIL_MODE`, `HERCO_REMINDER_LEAD_HOURS`, `SUPABASE_URL`, `SUPABASE_SECRET_KEY`; shop change-request inbox in the database.
- [ ] Google and Facebook login apps per environment with callback URLs, plus test users.
- [ ] GA4: `HERCO_GA4_MEASUREMENT_ID`, `HERCO_GA4_API_SECRET` after consent wording is approved.
- [ ] Photo cleanup worker: `HERCO_PHOTO_CLEANUP_URL`, `HERCO_PHOTO_CLEANUP_SECRET_KEY`, `HERCO_PHOTO_CLEANUP_RETENTION_DAYS`, `HERCO_PHOTO_CLEANUP_MODE`.
- [ ] Backup runner: private machine, backup folder, age key pair, PostgreSQL backup login, `HERCO_MEDIA_*` keys, `HERCO_BACKUP_ALERT_WEBHOOK`, independent encrypted storage.
- [ ] External uptime checks and alert destination.
- [ ] Staging evidence: live sign-in and cross-device test, concurrent booking and points tests on hosted PostgreSQL, real-phone review, email delivery test, restore drill, production speed traces, then a written release go-ahead.

## Done log
- 2026-11-17 M1 Performance and security pass on the demo: images 86% smaller, safer storage parsing, CSP, theme and keyboard fixes.
- 2026-11-17 F-007 Booking history filters (date, status, search) and pagination in the demo.
- 2026-11-19 Production plan updated; password-staff migration written.
- 2026-11-20 First 31 database migrations applied to the hosted Supabase project; email sign-up via Brevo SMTP verified by the maintainer.
- 2026-11-20 F-012 First Owner set up (10 pages, 19 actions).
- 2026-11-20 F-012 Password-only staff sign-in approved and applied.
- 2026-11-20 UI parity audit written; customers, activity log and staff header matched to the demo; migrations 033–036 and TEST seed data applied (36 total).
