# Booking email worker

The application records booking notifications in the private database outbox. A separate Cloudflare Worker claims up to five messages every five minutes and sends them through Brevo. Hosting the email worker separately keeps its privileged database credential out of the site Worker and browser.

The worker delivers booking request receipts, confirmations, and customer decisions on cancellation and rescheduling requests. It can also send appointment reminders and notify the shop when a customer requests a cancellation or reschedule. Supabase manages authentication emails through its separately configured SMTP provider.

## Environment settings

| Binding | Value |
| --- | --- |
| `HERCO_EMAIL_MODE` | `disabled` by default. Set to `allowlist` for staging or `live` for an approved production worker. |
| `HERCO_REMINDER_LEAD_HOURS` | `0` by default. Set an approved lead time from `1` to `168` hours to enable reminders. |
| `SUPABASE_URL` | Project URL that matches the worker's environment. |
| `SUPABASE_SECRET_KEY` | Supabase secret key kept in the email Worker's secret store. A legacy service-role key also works. |
| `BREVO_API_KEY` | Brevo transactional API key kept in the email Worker's secret store. |
| `EMAIL_FROM` | Sender address verified by Brevo. |
| `EMAIL_REPLY_TO` | Optional monitored address for replies. |
| `STAGING_EMAIL_ALLOWLIST` | Comma-separated inboxes for staging sends. Required in `allowlist` mode. |

Apply the database migrations in order and configure the worker separately from the SvelteKit application. The Wrangler configuration is [wrangler.email.jsonc](../wrangler.email.jsonc). Use Wrangler with `--config wrangler.email.jsonc` for configuration, secrets, and deployment. Keep production and staging Workers and settings separate. Use the staging project and an approved test inbox to verify delivery before enabling production sends. Leave the worker disabled until setup is approved.

## Staff change-request inbox

Staff email starts disabled in each database. An authorized project database operator can replace the example address below with the approved shop inbox after the email Worker is ready. For staging, add that test inbox to `STAGING_EMAIL_ALLOWLIST`.

```sql
update herco_private.staff_notification_settings
set change_request_inbox = 'approved-shop-inbox@example.test'
where singleton;
```

Set the field back to `null` to stop queueing staff notifications. Only requests submitted while an inbox is configured enter this queue. The email includes references and dates so staff can review the request securely in the app. Requests stay open for manual handling. Sending or skipping an email has no effect on request status.

## Delivery outcomes

- Successful API acceptance records Brevo's message ID. Actual inbox delivery can be checked in Brevo.
- An explicit rate limit retries after the provider delay or the worker's increasing backoff, whichever is longer, capped at 24 hours and five attempts.
- A provider rejection or invalid template stops that job. A staging recipient outside the allowlist is recorded as skipped.
- A timeout, ambiguous response, or expired lease puts the job in review. Compare it with Brevo's transactional logs before deciding whether to requeue it. A Worker crash can occur after Brevo accepts the send and before the database records the message ID.
- Reminders are queued once per confirmed appointment schedule and checked again immediately before contacting Brevo. A reminder is skipped if the appointment has passed, was cancelled, moved, or changed to a different recipient by then. A booking change submitted after the final check can still overtake a send already in progress.
- Staff change-request notifications also recheck the configured inbox and pending request before sending. A closed or withdrawn request, or a changed inbox, causes the queued mail to be skipped.

An operator with database access can review job counts without exposing addresses or email content.

```sql
select last_outcome, count(*)
from herco_private.notification_outbox
where failed_at is not null or review_at is not null
group by last_outcome;
```
