# F-017: 6-month maintenance reminder email
> New idea from the owner, 2026-11-23 (Q-13 answer).

**Status:** Ready (approved 2026-11-23) · **Milestone:** M2 · **Depends on:** F-002, F-007, F-014

## In one sentence
Six months after staff mark a job Done, the customer gets an email at 9 AM inviting them back for maintenance, with the shop's booking hours and an unsubscribe link.

## Owner answers (record)
- 2026-11-23, owner's words: "Once a ceramic coating, powder coating is mark as completed, we should remind them on the 6th month as it is maintenance."
- 2026-11-23: every job marked Done triggers it, not only ceramic and powder coating.
- 2026-11-23: skip the reminder if the customer already has an upcoming booking (Pending or Confirmed) on the send day.
- 2026-11-23 Q-26: wording as drafted below is fine; send at 9 AM Philippine time (shop opening) and say in the email that customers can book from 9 AM to 5 PM (the admin's current default hours); add an unsubscribe link.

## User steps (exactly how it works)
1. Staff mark a booking **Done**.
2. In the same save, an email job is queued for 9:00 AM Philippine time, 6 months after the Done date, e.g. Done Jan 10 → sent Jul 10, 9 AM.
3. On the send day the email Worker checks again, then sends the email.
4. If the customer clicks **Unsubscribe from reminders**, they see "You won't get maintenance reminders any more." Booking emails (received, confirmed, decisions, 24-hour reminder) keep coming.

## Email wording (approved draft)
- Subject: "Time for maintenance? It's been 6 months"
- Body: "Hi {first name}, it's been 6 months since your {service names} at HERCO. Time for maintenance? You can book any time from {opening hour} to {closing hour}, {open days}. Book here: {link to /book}"
- Footer: "Don't want these reminders? Unsubscribe" (link).
- `{opening hour}`, `{closing hour}` and `{open days}` come from the admin's default hours (F-002) at the moment of sending, e.g. "9 AM to 5 PM, Wednesday to Sunday", so the email stays correct if the admin changes them.

## Rules and details
- One reminder per Done booking. If a booking is set back from Done, the reminder is cancelled.
- Skipped if, on the send day, the customer has a Pending or Confirmed future booking, has unsubscribed, the account is gone, or the email changed.
- Unsubscribe only stops maintenance reminders, for that customer, for all future Done jobs. It needs no sign-in. A signed-in customer can turn reminders back on from the Account page (Appearance-style switch "Maintenance reminders").
- Uses the existing outbox and Brevo worker (F-014): an email failure never affects bookings.
- The email shows only the customer's own first name and service names; no prices, notes or staff names.

## Screens
- Unsubscribe page `/reminders/unsubscribe`: one sentence and a **Confirm unsubscribe** button (so link scanners in email apps don't unsubscribe by accident). States: confirm, done ("You won't get maintenance reminders any more."), link invalid or expired ("This link doesn't work any more. Sign in to change reminder settings in your Account."), error with retry.
- Account page: a "Maintenance reminders" on/off switch in the Profile card.

## Data
- New outbox template `maintenance_reminder`, `available_at` = 9:00 AM Asia/Manila on the date 6 months after Done; unique per booking.
- New table `herco_private.reminder_opt_outs` (`customer_id` primary key, `created_at`). RLS on; no direct browser access.
- Unsubscribe token: a signed, single-purpose token (customer id + purpose + expiry 1 year), made by the worker with a server secret; it never contains the email address.

## API (to add to `docs/api-contract.md`)
- `POST /api/reminders/unsubscribe` — anyone with a valid token. Input `{ token }`. Success `204`. Errors `400` invalid or expired token, `503`. Rate-limited.
- `GET /api/account/reminders` and `PUT /api/account/reminders` `{ maintenance: boolean }` — signed-in customer, own setting only. Errors `401`, `400`, `503`.

## Edge cases and errors
- Booking Done twice (undo then Done again) → only one reminder.
- Customer booked again before the send day → skipped.
- Six months lands on a date that doesn't exist (Aug 31 → Feb 28/29) → last day of that month.
- Send day is a closed weekday → still sent at 9 AM (it's an email, not a visit).
- Admin changed hours since the job → email shows the new hours.
- Unsubscribe clicked twice or token reused → still "done", no error.
- Forged or edited token → `400`, nothing changes.

## Must not break
- Marking a booking Done (F-007), points (F-010), other emails and the 24-hour reminder (F-014), opening hours (F-002).

## Acceptance tests (all must pass)
- [ ] Marking Done queues one reminder for 9 AM Philippine time, 6 months later.
- [ ] The email shows the admin's current default hours and open days.
- [ ] An upcoming booking on the send day skips it.
- [ ] Undoing Done cancels it.
- [ ] Unsubscribe stops future maintenance reminders but not booking emails; the Account switch turns them back on.
- [ ] Forged, expired or other customers' tokens change nothing.
- [ ] Email failure leaves the booking unchanged.

## Ready checklist (no code until all are ticked and the owner approves)
- [x] Every user step is written out
- [x] Rules, limits and permissions are decided
- [x] Screens and their states are described
- [x] Data and API are designed
- [x] Edge cases and "must not break" are listed
- [x] Acceptance tests are written
- [x] No open questions left
- [x] **Owner approved:** 2026-11-23, in chat ("approve the f017 so u can start")
