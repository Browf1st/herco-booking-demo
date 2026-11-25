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
| F-002 | Availability, date overrides and slot blocks | Testing: opening hours built 2026-11-23 (both builds); migrations applied to hosted Supabase 2026-11-24; staff screens not yet checked signed in | F-012 | [spec](features/F-002-availability.md) |
| F-003 | Coating catalog, pricing rules and promotions | Blocked: approved price list not supplied (Q-05, Q-06) | F-012 | [spec](features/F-003-catalog-pricing.md) |
| F-004 | Service change and promotion history | Testing | F-001, F-003 | [spec](features/F-004-service-history.md) |
| F-005 | Customer account and sign-in | Testing (Google login works locally; Facebook dropped) | none | [spec](features/F-005-account-sign-in.md) |
| F-006 | My Bookings and change requests | Needs answers (Q-08, Q-12) | F-001, F-005 | [spec](features/F-006-my-bookings.md) |
| F-007 | Staff booking queue, calendar and booking history | Testing: staff price edits, added services and Changes history built 2026-11-24 in the Bookings popup; migrations 202611240001-002 not yet applied | F-002, F-012 | [spec](features/F-007-staff-queue.md) |
| F-008 | Manual booking, walk-in and intake form | Blocked: approved form text and signature method (Q-01, Q-02) | F-005, F-012 | [spec](features/F-008-manual-walk-in-intake.md) |
| F-009 | Completion with photos and exact prices | Blocked: photo retention not decided (Q-03); private bucket checked | F-003, F-007 | [spec](features/F-009-completion-photos.md) |
| F-010 | HERCO Points and rewards | Needs answers (Q-14) | F-005, F-012 | [spec](features/F-010-points-rewards.md) |
| F-011 | Reports and activity log | Needs answers (Q-04); Reports v2 revisions built 2026-11-24 (read-only details) | F-009, F-012 | [spec](features/F-011-reports-activity-log.md) |
| F-012 | Staff access and roles | Needs answers (Q-11); first Owner set up | F-005 | [spec](features/F-012-staff-access.md) |
| F-013 | Inventory and stock exports | Testing (opening counts needed, Q-15) | F-012 | [spec](features/F-013-inventory.md) |
| F-014 | Email notifications (Brevo worker) | Testing: first booking email sent locally in allowlist mode; events, 24-hour reminder and shop inbox decided; templates await Q-13 | F-001, F-006 | [spec](features/F-014-email-notifications.md) |

UI parity: the Worker screens are being matched to the demo look. Open items in docs/ui-parity-audit.md (Q-18).

### Owner revision list, 2026-11-23 (designs approved by the owner the same day)
| Item | Request | Status | Spec |
|---|---|---|---|
| A | Showcase revamp: all 91 unique shop photos, masonry wall, category filters, photo viewer; Home shows 4 photos + "See all" | Done | [F-001](features/F-001-customer-booking.md) |
| F-018 | Ceramic and Powder Showcase tabs | Done locally | [spec](features/F-018-ceramic-showcase.md) |
| 11 | HERCO Points ranking number did not follow the sort | Done: # is always the real points rank | [F-010](features/F-010-points-rewards.md) |
| 12 | Page titles differ between staff tabs | Done: one Reports-style header on every staff tab, both builds | [F-007](features/F-007-staff-queue.md) |
| 13 | Saving staff access gave an error; why "Restricted Admin"? | Done: form crash fixed; "Restricted Admin" removed (roles are labels only) | [F-012](features/F-012-staff-access.md) |
| 14 | Where should the light/dark switch go? | Done: moved out of the top strip into the staff account menu and the footer (System / Light / Dark); the Account page Appearance section stays | [F-005](features/F-005-account-sign-in.md) |
| 15 | Reports too crowded | Done: income first, period chips, "Filters (n)", table on desktop / cards on phone, details in a popup sheet, filters apply instantly | [F-011](features/F-011-reports-activity-log.md) |
| 16 | Staff Bookings and Booking history too noisy; "tap to view more" | Done: calm booking cards (time, status, name, "Bike · N services", one main button, "⋯" menu, Details), details in the same popup sheet; History is a flat list with date and time per card | [F-007](features/F-007-staff-queue.md) |
| 17 | Sample of a change request | Done: the demo's two fictional requests (Admin view → Booking → Change requests); nothing added to Supabase | [F-006](features/F-006-my-bookings.md) |
| 18 | Activity log: 10 per page | Done, both builds | [F-011](features/F-011-reports-activity-log.md) |

Follow-up fixes (2026-11-23): the booking card "⋯" menu closes on a tap elsewhere or Esc; the phone Back button closes the booking details sheet (no extra history entries); the Manage HERCO Points popup search no longer replaces the Points ranking list (it has its own results).

### M3: Release and operations
| ID | Feature | Status | Depends on | Spec |
|---|---|---|---|---|
| F-015 | Backups, photo cleanup and restore drill | Blocked: storage, schedule and recovery targets not chosen (Q-16) | F-009 | [spec](features/F-015-backups-recovery.md) |
| F-016 | Staging hardening, monitoring, analytics and production release | Blocked: hosting, domain, alerts and owners not confirmed (Q-17) | all M2 | [spec](features/F-016-release-monitoring.md) |
| F-017 | 6-month maintenance reminder email | Testing: built 2026-11-23; migration applied 2026-11-24; needs `HERCO_REMINDER_TOKEN_SECRET` and `HERCO_SITE_URL` | F-002, F-007, F-014 | [spec](features/F-017-maintenance-reminder.md) |

## Questions waiting for you
- [x] Q-01 F-008: How do customers sign the walk-in form? Answered 2026-11-21: customers sign in to their own account to sign it (already built), with the typed full name plus tick box.
- [ ] Q-02 F-008: Please supply the final form title, full text, version name and who approves it.
- [ ] Q-03 F-008/F-009: How long do we keep completion photos and signed forms, and who can see them? (A) staff only, kept 1 year (B) customer can also see photos (C) other. Unlinked uploads are deleted after (A) 7 days, the minimum (B) 30 days.
- [ ] Q-04 F-011: Do you need "collected revenue" (money actually received) in reports? (A) no, show only "Completed service value" (B) yes, then name the source, e.g. a cash book, and the rules for discounts and refunds.
- [ ] Q-05 F-003: Please supply the approved catalog: service names, fixed prices or ranges, which need a shop quote, exact bike models, finishes, parts and wheel sizes.
- [ ] Q-06 F-003: Promotions: (A) one active promotion at a time, as built (B) several at once. Which promotions run first?
- [x] Q-07 F-002: Answered 2026-11-21: the admin sets the general opening hours (e.g. 9 AM–5 PM) for all dates; every slot is bookable unless the admin blocks it, and can be reopened later; no service durations. Admin-editable opening hours is new work (spec needed, see F-002).
- [x] Q-07 follow-up F-002: Answered 2026-11-23: the admin sets default hours for all dates (e.g. 8 AM–8 PM) and the open weekdays; each date can have its own hours and an hour checklist; shorter hours keep existing bookings and warn the admin. Real hours stay 9 AM–5 PM (8–8 was an example). Spec approved 2026-11-23.
- [x] Q-07b F-002: Answered 2026-11-23: (C) no limit per hour; the admin blocks the hour when the shop is full.
- [ ] Q-08 F-006: Limits on changes: (A) customers can cancel or reschedule anytime, staff decide (B) not within 24 hours of the visit. Do open requests expire? Does the old time stay held while a reschedule waits?
- [ ] Q-09 F-001: Guest booking without an account: (A) keep off, sign-in required, as built (B) allow guests, with rules for claiming the booking later.
- [ ] Q-10 F-008: Manual bookings for customers with no account: (A) staff can only book for verified accounts, as built (B) staff can create a booking and link it later.
- [ ] Q-11 F-012: Confirm the role list and the pages and actions each role gets: Owner, Superadmin, Admin, Staff. Who is the Superadmin? (2026-11-23: "Restricted Admin" dropped by the owner; roles are labels and access comes from the ticked pages and actions.)
- [ ] Q-12 F-006/F-007: Can customers see the shop's approval notes? (A) no, staff only (B) yes, a separate customer-facing note.
- [ ] Q-13 F-014: Approve the email wording (templates). Partly answered 2026-11-23: change-request emails go to the owner's own Gmail for now (saved only in the database, not in Git); customers get booking received, booking confirmed, change request decided, and a reminder 24 hours before the visit; plus a new 6-month maintenance reminder (F-017).
- [x] Q-26 F-017: Answered 2026-11-23: the drafted wording is fine; sent at 9 AM Philippine time and says customers can book from 9 AM to 5 PM (the admin's current hours); unsubscribe link added.
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
- [x] Q-24 Photos: "Replace photos with gdrive": answered 2026-11-20 as (B) site pictures. The owner supplied the "Showcase for powder coating" folder, now shown on the Showcase page. Completion photos stay in the private Supabase bucket.
- [x] Q-25 UI proposals from the 2026-11-20 bug list: approved and built 2026-11-20 (code screen with digit boxes, account layout, smaller fonts, My Bookings sections).

## Needs you (accounts, keys, content)
Enter secret values only in the provider's settings or ignored local files, never in chat or Git.
- [ ] Isolated Supabase staging project (and later a separate production project), with migration and Auth/Storage access for the maintainer. Values: `PUBLIC_SUPABASE_URL`, `PUBLIC_SUPABASE_PUBLISHABLE_KEY`.
- [ ] Cloudflare account and billing owner, staging hostname, production domain and DNS owner. Values: `APP_ORIGIN`, `APP_ENV`.
- [x] Private Storage bucket `herco-completion` (JPEG/PNG/WebP, 4 MB) on the dev project, checked 2026-11-20. Still needed on staging and production, plus `HERCO_STORAGE_SECRET_KEY` in each deployed site Worker.
- [x] Brevo locally: API key in the gitignored `.dev.vars.email`; one test booking email sent and accepted (2026-11-20). Also done locally: `EMAIL_FROM`, `EMAIL_REPLY_TO`, `STAGING_EMAIL_ALLOWLIST`, Supabase Auth SMTP. Still needed for production: sending domain and DNS.
- [x] Local email worker settings: `HERCO_EMAIL_MODE=allowlist`, `HERCO_REMINDER_LEAD_HOURS=0`, `SUPABASE_URL`, `SUPABASE_SECRET_KEY`. Shop change-request inbox set in the hosted database on 2026-11-23 (owner's Gmail). Set `HERCO_REMINDER_LEAD_HOURS=24` when reminders go on.
- [x] Google login app for local testing: Google Cloud project "HERCO dev", client in Supabase, redirect URL `http://localhost:5175/api/auth/callback` saved; full login passed (2026-11-20). Still needed per environment: staging and production origins, app publishing and branding. Facebook login dropped by the owner (setting off).
- [ ] Maintenance reminders (F-017): set the same random `HERCO_REMINDER_TOKEN_SECRET` (32+ characters) in the email Worker and the site Worker, and `HERCO_SITE_URL` in the email Worker. Optional: a Cloudflare rate-limit rule on `/api/reminders/unsubscribe` (the app has no rate limiter; the spec asked for one).
- [x] Migrations 202611230001-004 (opening hours, maintenance reminder, records sort, public shop hours): CI database tests pass (run 14); applied to the hosted Supabase project on 2026-11-24 with the owner's OK (Free plan, so no backup was possible); recorded in `supabase_migrations.schema_migrations` (41 total).
- [ ] GA4: `HERCO_GA4_MEASUREMENT_ID`, `HERCO_GA4_API_SECRET` after consent wording is approved.
- [ ] Photo cleanup worker: set up locally in `.dev.vars.cleanup` (report mode, 30-day placeholder retention); a report run found 0 photos to delete. Still needed: the retention answer (Q-03) before `active`, and a deployed Worker.
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
- 2026-11-20 Local setup: Google login working end to end, Facebook dropped (F-005), email worker set to allowlist mode and first booking email sent (F-014), photo bucket checked and cleanup run in report mode with 0 to delete (F-009, F-015).
- 2026-11-20 F-001 bug fixes (code only, not yet tried in the app while signed in): review pop-up time no longer shows "undefined", mobile number optional for online bookings (new migration 037, not yet applied to hosted Supabase), and customers go to My Bookings with status after submitting.
- 2026-11-20 UI updates (F-005, F-006, F-010): "Check your email" code screen with one box per digit and a Resend code link (new `resend` account action, `HERCO_AUTH_OTP_LENGTH` setting, default 6); account page with Profile, Appearance and Sign out sections; smaller type on My Bookings and HERCO Points; My Bookings split into Upcoming, Requests, Completed and Cancelled. Account, Points and My Bookings checked signed in on local dev; the code screen was not seen in the browser (needs a fresh signup).
- 2026-11-20 QA and misuse-test fixes: code boxes keep digits in place when one is cleared; My Bookings waits for change requests before showing sections and has a Past section for completed or past-dated visits; the booking server now checks a typed mobile number (7-15 digits).
- 2026-11-20 Showcase (`/preview`): powder coating section replaced with a gallery of the shop's own photos (10 tiles plus the HERCO Concept poster, WebP at 480/800 px, camera data removed); finish names link to booking. Both builds and size budgets pass.
- 2026-11-21 Migration 037 (optional online mobile) applied to the hosted Supabase project via the Dashboard SQL editor with the maintainer's go-ahead; check query confirmed online bookings accept a blank mobile, staff bookings still need one, and browsers cannot call the function directly (37 total). Also recorded in `supabase_migrations.schema_migrations` like 001-036.
- 2026-11-23 Owner UI requests: home page Powder coating card and "Wheel coating colours" now use the shop's own photos (8 named finishes: Fire Red, Fire Pink, Fire Violet, Fire Aqua Teal, Fire Gold, Chrome Black, High Gloss White, Miko Silver; WebP 480/720 px, 2 columns on phones, 4 on desktop); HERCO Points reward name and cost on one line (F-010); new login and sign-up card with tabs and show-password (F-005), social buttons unchanged. Both builds and size budgets pass; checked at phone and desktop width, light and dark. Signed-in Points cards not seen in the browser.
- 2026-11-23 Showcase revamp (owner item A): all 91 unique photos from the owner's "HERCO POWDER COATING" folder (16 exact copies removed, 2 sideways DNG photos turned upright, 1 screenshot's black bars cropped; 2 videos not used), WebP 480/960 px without camera data in `static/photos/showcase/`. Masonry wall, filter chips (Two-tone, Wheel colours, On the bike, Small parts), "Show 24 more", full-screen viewer with next/previous, arrow keys, swipe, Esc and phone Back, "Book this finish". Home's 8 colour cards and slider replaced by 4 photos + "See all 91 in Showcase". The old 10-photo gallery files were removed. The size budget now checks every Showcase file (480 ≤ 110 KiB, 960 ≤ 320 KiB).
- 2026-11-23 Staff fixes: Staff Access form no longer crashes when Bookings and Booking history are both ticked (item 13; reproduced in the browser first), "Restricted Admin" removed from the form; Points ranking keeps each fan's real rank in every sort and search (item 11); one page header style on all staff tabs in both builds (item 12); Activity log shows 10 per page (item 18). Regression tests added.
- 2026-11-23 Staff Reports, Bookings, Change requests and Booking history redesigned (items 15, 16) in both builds: one shared details popup replaces every "Tap to view more"; filters apply as they change. Live screens checked signed in (read only, nothing saved). Demo `admin` JS 123.9/124 KiB and Worker `admin` CSS 12.0/12 KiB: both at their limits. To fit, the demo's other paged lists now share the centred pager and its status filters no longer show counts.
- 2026-11-23 F-002 opening-hours spec written from the owner's answers (default hours, open weekdays, per-date hours and checklist, no limit per hour, shorter hours keep bookings); approved by the owner, now Ready.
- 2026-11-23 Built (both builds, not yet run against a database): F-002 opening hours (default hours and open days, per-date own hours and hour checklist, no limit per hour, outside-hours warning, stale-save protection, home and footer hours from the settings); F-017 6-month maintenance reminder (queued on Done, 9 AM Manila, skip rules, unsubscribe page and Account switch, List-Unsubscribe header); Booking Reports layout v2 (F-011: income card, count cards, full-width table, More details popup, Book menu, server-side sort, estimates; money now also hidden by the server without viewIncome); Account menu with theme in the header, theme removed from the footer (F-005). QA and misuse findings fixed. Left open: a booking made during a default-hours save can land outside the new hours (shown as Outside hours); staff day view still sends prices to staff without viewIncome (existing behaviour). svelte-check 0 errors, 165/165 tests, both builds and budgets pass. New migrations 202611230001-004 not applied.
- 2026-11-24 CI database tests fixed (test-only mistakes: public shop hours allowlist, private reads under a signed-in role, fixtures, a plpgsql CASE) and passing; migrations 202611230001-004 applied to the hosted Supabase project with the owner's OK and checked (hours still 9 AM-5 PM Wed-Sun, 9 bookings kept, old one-per-hour index gone). Live app on local dev reads shop hours and availability from them; staff screens not yet checked signed in. Q-13 partly answered (F-014) and new F-017 maintenance reminder added. Shop change-request inbox set to the owner's Gmail in the hosted database via the SQL editor with the owner's OK (checked: 1 settings row, address matches).
- 2026-11-24 Owner revisions built (live Worker build; the GitHub Pages demo is no longer updated, owner 2026-11-24, but still compiles): staff edit each service's price after inspection (reason required, logged) and add/remove services; a Changes history; customers see the updated price with the original struck through, and can no longer edit services once the shop changed a price (F-007). Booking actions moved to a new Bookings tab popup with the Reports design (approve, reschedule, cancel, complete, price edits, add/remove, notes); Reports details are read-only (F-011). Reports: search box, Date oldest and Price low-high sorts, no extra labels. Header: one SIGN IN / ACCOUNT menu on the right in the tab font (F-005). Showcase: every photo shows its name on the image; Show more no longer jumps. Customers tab fixed (lookups failed in read-only mode since 2026-11-20) and now lists customers who never booked (staff excluded). Staff Access preview card (F-012); "How booking works" title; Privacy link hidden; red Apply dates; broken characters in the Bookings slot filter fixed. svelte-check 0 errors, 212 tests, both builds and budgets pass. New migrations 202611240001-002 not yet applied; staff screens not yet checked signed in.
