# F-014: Email notifications (Brevo worker)
> Documented from existing docs on 2026-11-20 — owner to confirm.

**Status:** Testing (first booking email sent locally; templates, events and reminders await Q-13) · **Milestone:** M2 · **Depends on:** F-001, F-006

> 2026-11-20 delivery test: a new restricted Brevo key ("HERCO dev - Booking Emails", transactional email only) is in `.dev.vars.email`. A real test booking queued a `booking_submitted` job, and one worker run sent it to the owner's allowlisted inbox: Brevo returned 201 and the outbox recorded `accepted` on the first attempt. The older unused key ending `t4F8S3` is still active in Brevo.

> 2026-11-20 local setup: the gitignored `.dev.vars.email` now has `HERCO_EMAIL_MODE=allowlist`, `HERCO_REMINDER_LEAD_HOURS=0` (reminders off until Q-13), `EMAIL_FROM` and `EMAIL_REPLY_TO` set to the Brevo-verified sender, and `STAGING_EMAIL_ALLOWLIST` limited to the owner's own two inboxes. `BREVO_API_KEY` was added by the owner (see the delivery test above). Supabase Auth SMTP is on (`smtp-relay.brevo.com`, port 587, Brevo SMTP login). `wrangler.email.jsonc` still ships `disabled`, and no email Worker is deployed. The outbox was empty when checked.

## In one sentence
Customers get emails when they book, when the shop confirms, and when a change request is decided, and the shop gets an email for new change requests.

## User steps (exactly how it works)
1. A booking action saves an email job in the private outbox, in the same save as the booking.
2. A separate Cloudflare email Worker picks up to 5 jobs every 5 minutes and sends them through Brevo.
3. Customer receives: booking receipt, confirmation, cancellation/reschedule decision, optional reminder.
4. Shop inbox (if set) receives new change-request notices with references and dates.

## Rules and details
- Sign-in emails (verify, reset) go through Supabase Auth with Brevo SMTP, separate from this worker.
- `HERCO_EMAIL_MODE`: disabled (default), allowlist (staging), live (approved production).
- Retries: rate limits back off up to 24 hours and 5 attempts; rejections stop; timeouts go to review.
- Reminders recheck the appointment just before sending; skipped if passed, cancelled, moved or recipient changed.
- An email failure never undoes a booking. Exactly-once delivery is not promised.
- The browser never holds the Brevo key; the worker's secret key stays only in that worker.
- Templates, events, recipients, reminder timing, shop inbox: TBD — ask owner (Q-13).

## Screens
- None for customers. Operators check failed/review jobs with a database query (no addresses shown).

## Data
- `herco_private.notification_outbox`, `herco_private.staff_notification_settings`.

## API
- No public endpoints; worker uses the database directly.

## Edge cases and errors
- Worker crashes after Brevo accepted → job in review; compare with Brevo logs before requeue.
- Staging recipient outside allowlist → skipped.
- Request withdrawn before the shop email sends → skipped.

## Must not break
- Booking saves (F-001) and request status (F-006).

## Acceptance tests (all must pass)
- [ ] Staging: receipt, confirmation and decision emails reach the allowlisted inbox. (Receipt sent locally on 2026-11-20; confirmation and decision emails not yet tested.)
- [ ] Brevo outage leaves bookings intact and jobs retry.
- [ ] Reminder is skipped for a cancelled or moved booking.
- [ ] Recovery after worker interruption.

## Ready checklist (no code until all are ticked and the owner approves)
- [x] Every user step is written out
- [ ] Rules, limits and permissions are decided
- [x] Screens and their states are described
- [x] Data and API are designed
- [x] Edge cases and "must not break" are listed
- [x] Acceptance tests are written
- [ ] No open questions left
- [ ] **Owner approved:**
