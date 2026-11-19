# Performance, security and Supabase/Brevo implementation

Updated 2026-11-19. This roadmap tracks the production migration in the existing HERCO repository. The current deployment is the GitHub Pages demo.

## Confirmed corrections

- Preserve the existing SvelteKit UI, still-photo homepage, Showcase, and compact My Bookings cards with inline View details and request actions in the header. Keep the demo available during staging. Verify theme choices before release.
- Keep customer payments, deposits, and Announcements outside the production migration. Report recorded final charges as **Completed service value**. Collected revenue requires an approved internal source and adjustment rules.
- Preserve scheduled manual booking and walk-in intake. Attribute staff actions to verified identities and securely link bookings to customer accounts. Keep intake forms and evidence private.
- Label elapsed Philippine-time hours **Past slot** in both admin views and suppress new block actions on elapsed hours. Offer **Unblock** only for a saved manual restriction. Leave existing appointments in place when a date closes.
- Require an exact saved price for every unresolved quote or range and one to three private photos for new completions. Recheck these rules inside the completion transaction. Preserve historical completed records.
- Store the applied promotion identifier and display label with the saved pricing snapshot. Keep original service lines and prices and append later changes. Preserve prior points and reward activity when settings change.
- Record the booking ownership decision before public staging acceptance. Use verified sign-in for the first slice. Keep guest submission and account claiming disabled until their rules are approved and tested.

## Production implementation checklist

Check off each milestone after its acceptance checks pass. Record the tested revision, environment, and evidence in [the handoff](production-handoff.md). Use fictional fixtures, mail stubs, and unconfigured environment bindings while account setup is underway. Keep live credentials in the provider or runner's secret store. Features that depend on an unconfigured provider or unresolved business rule should remain disabled there. Production release requires real configuration and staging verification.

1. [ ] **Capture the demo baseline.** Record the approved local revision, carry the My Bookings edits into the migration baseline, and preserve the GitHub Pages release. Run type checks and build, then capture booking, admin, points, inventory, and mobile behavior. Add focused browser, PostgreSQL, and business-rule tests for the workflows being migrated.
2. [ ] **Set up the server build and environment contract.** Keep the same repo. Add request-scoped SvelteKit server code, an example environment file containing names and placeholders, and separate local, staging, and production configuration. Use Cloudflare Workers as the proposed deployment target pending hosting confirmation. Keep demo state and fixtures out of production request handlers. Verify the build, isolated configuration, and startup behavior with missing required bindings.
3. [ ] **Create the database and access foundation.** Version Supabase migrations for customer profiles, staff memberships and capabilities, service/pricing snapshots, booking ownership, date/slot restrictions, booking events, private evidence metadata, and the notification outbox. Add constraints and row-level security. Test a clean rebuild, an upgrade, direct access by different identities, and denial of self-promotion.
4. [ ] **Wire verified identity.** Integrate Supabase Auth sessions and callbacks, sign-in, logout, email verification and reset. Enforce staff permissions and privileged MFA on the server. Remove the production demo role switches. Test expiry, recovery, revoked grants, and ownership. Add and test Google and Facebook when each provider is configured.
5. [ ] **Deliver the customer booking slice.** Implement public availability, service selection, submission, confirmation, and My Bookings for signed-in customers. Recheck shop-local time, restrictions, trusted prices, and capacity in the write transaction. Save the original booking, history event, and outbox job together. Verify concurrent submissions, safe retries, and private booking reads.
6. [ ] **Migrate the staff booking workflows.** Implement open/close/restore date, block/unblock slot, elapsed-slot labels, manual scheduled bookings, walk-ins, approval notes, service edits, and customer cancellation/reschedule review. Keep private notes out of customer views. Verify that date closures preserve existing appointments and that schedule changes and approvals cannot race into an invalid slot.
7. [ ] **Enforce completion and private evidence.** Implement versioned walk-in forms, protected uploads, authorized reads, completion pricing checks, and audited status updates. Verify that missing or unrelated photos, invalid files, and unresolved prices prevent completion. Verify that retries cannot repeat completion effects.
8. [ ] **Migrate points, rewards, inventory, pricing, and reports.** Use transactional ledgers and trusted prices. Preserve promotion snapshots and reward receipt/claim attribution. Scope report rows, totals, exports, and audit details independently. Test duplicate awards, claims and deductions, historical prices and balances, and reconciliation of Completed service value.
9. [ ] **Connect and operate email.** Configure Brevo SMTP for Supabase Auth and use the Brevo API for booking notifications. Run a scheduled outbox worker with retry limits, stale-reminder checks, and failed-job visibility. Test Auth links, staging recipient restrictions, delivery failures, cancellation and reschedule behavior, and recovery after a worker interruption.
10. [ ] **Harden staging and rehearse operations.** Run the full suite, including real-device accessibility and performance checks, database races, access revocation, protected photos, and end-to-end notifications. Set up error and uptime alerts and approved analytics. Rehearse restoring database and file backups in isolation and rolling back to a compatible application release. Rehearse a validated import if real records are supplied.
11. [ ] **Release and verify production.** Review staging acceptance, confirm the release revision and migration order, verify domain and secret bindings, obtain release authorization, then deploy and run smoke checks. Confirm staff access, live email, monitoring, backup freshness, and the rollback decision owner. Track any follow-up using the handoff.

## Configuration you can do in parallel

These are setup tasks for the account or business owner. The example names are placeholders for the environment contract and may be mapped to the chosen host's bindings. Share project references, URLs, configuration status, and credential types as needed. Enter secret values directly in the appropriate environment.

| Needed by | Owner configuration | Development placeholder or fixture |
| --- | --- | --- |
| Staging database and Auth | Identify which project the existing dev keys belong to. Prepare an isolated Supabase staging project and grant an authorized maintainer migration and Auth/Storage configuration access. Record the project URL and publishable key. Set up a separate production project before release. | `PUBLIC_SUPABASE_URL`, `PUBLIC_SUPABASE_PUBLISHABLE_KEY`, local database and fictional accounts. Keep migration and any necessary elevated worker credentials separate from public bindings. |
| Staging deployment | Confirm server host, account and billing owner, staging hostname, and restricted deployment access. Identify the production domain and DNS owner. Configure separate staging and production deployment environments and secret bindings. | `APP_ORIGIN`, `APP_ENV`, local server. Cloudflare Workers is the proposed target. |
| Booking and staff acceptance | Confirm guest booking policy, manual booking account linking, role grants, first Owner and Superadmin, slot capacity and duration, request expiry and change windows, and approval note visibility. | Sign-in-only first slice, fictional staff and customers, demo capacity in tests, explicit test-only booking policy. |
| Walk-in and operations acceptance | Supply the approved intake form and signature method, evidence visibility and retention, service and pricing catalog, promotions, points and reward settings, inventory opening counts, and any approved import data. Confirm whether collected-revenue reporting is required. | Fictional intake and catalog fixtures, test photos and ledgers. Unapproved intake or financial rules stay out of release configuration. |
| Email staging test | Set up Brevo API access, separate SMTP credentials for Supabase Auth, verified sender and sending domain, DNS records, reply-to mailbox, and approved test recipients. Approve templates, events, recipients and reminder timing. | `BREVO_API_KEY`, `EMAIL_FROM`, `EMAIL_REPLY_TO`, `STAGING_EMAIL_ALLOWLIST`, mail stub. Configure SMTP in Supabase. |
| Social login acceptance | Create or confirm Google and Facebook apps for each enabled environment, set callback URLs, and supply test users and any provider approvals. | Provider flags off until real callbacks can be verified. |
| Launch verification | Confirm budget, expected traffic, production and backup ownership, retention and recovery targets, alert recipients, GA4 property and consent choices, and release/rollback owners. | Disabled external reporting in local tests, a test alert sink, and an isolated restore target. |

## Demo baseline

Svelte 5 / SvelteKit 3 / Vite 8, adapter-static, client rendering and prerendered shells, deployed by the existing GitHub Pages workflow. Bookings and operations live in localStorage; email/Google/Facebook sign-in and Admin/Owner views are simulations. URL parameters, browser IDs, prices, points and actor labels are editable by the visitor. Use fictional information only. CSP and input checks cannot turn this demo into an authenticated system.

The current homepage uses a still photo; the historical video/canvas effect is no longer active. Three.js is not imported by current routes, so lazy-loading that unused component would not reduce current route downloads. Keep unused originals for future editing; only optimized assets are requested by the updated UI.

## Implemented in this pass

- WebP versions of the eleven public gallery/logo images, a 480px hero variant, explicit hero and showcase dimensions, below-fold comparison lazy loading and asynchronous gallery decoding. Originals retained. Hero remains high priority; Showcase's first comparison remains eager. Image URLs use the deployment base path.
- One reactive Map of points balances replaces ledger scans during each ranking comparison and each displayed member balance. Transactional checks still read the mutation's draft ledger. Ranking cost becomes O(entries + members log members), instead of O(entries × members log members).
- Production static CSP permits same-origin scripts with generated SvelteKit bootstrap hashes; object embedding is disabled and form destinations restricted. Inline styles remain allowed because controls use dynamic style attributes. Google Fonts is explicitly allowed. Development policy is unchanged for Vite tooling.
- Theme initialization moved to a same-origin script before paint. Browser theme color follows explicit light/dark and system preferences. Forms, autofill, dialogs and long card content use theme-aware colors and mobile sizing; comparison keyboard focus is visible and reduced motion is respected.
- Saved demo account/booking-ID parsing tolerates malformed JSON and rejects invalid account field types. Restored account fields are explicitly selected; booking IDs are deduplicated. This is robustness, not identity verification. Booking/operations blobs still need a proper recovery/export workflow for corrupt or full browser storage; never silently overwrite them with demo seeds in production.

## Measurement and budgets

Baseline: production build and Svelte diagnostics pass. Local Edge headless, 390×844 CSS px, DPR 1, empty browser context, local preview, no network/CPU throttling, fictional seeded data. Initial homepage image requests before changes totaled 2,808,480 bytes (logo, hero, before/after and service images). This is a resource observation, not a field Core Web Vitals result; lazy-loading thresholds vary by browser and viewport.

After changes, the same initial mobile view requested 381,846 image bytes (logo, 480px hero and service photos), a reduction of 86.4%. The comparison images load when approached while scrolling. This measures image payload only, not total transfer, LCP or load-time improvement.

| Asset | Original bytes | Delivered maximum variant bytes |
| --- | ---: | ---: |
| Hero | 1,169,499 | 161,536 |
| Logo | 200,682 | 2,892 |
| Ceramic application | 160,466 | 32,126 |
| Red-wheel service | 672,142 | 261,872 |
| Before + after | 605,691 | 189,828 |

WebP conversion: Sharp, quality 82, effort 6, no enlargement; logo width 160, wheel-set width 960, other images width 720, plus hero width 480. Preserve source aspect ratios. Recheck visual quality when changing originals. Local guardrails for this image set: largest hero <=170 KB, logo <=4 KB, service pair <=300 KB. These are asset budgets, not promises about network timing.

Before launch, collect repeated cold/warm production traces for home, booking, points, admin and Showcase on mobile/desktop and a representative Philippine network. Establish compressed route-JS and request budgets from those traces. Target field p75 LCP <=2.5s, INP <=200ms, CLS <=0.1; current local checks do not prove these targets. Validate image detail and layout on real devices, 200% zoom, keyboard and touch.

## Implementation sequence when proceeding

1. **Server hosting and environments.** Move from GitHub Pages/static adapter to a server-capable SvelteKit adapter, with isolated staging and production. Cloudflare Workers remains a proposed host. Confirm budget/region before provisioning. Remove global prerendering for authenticated routes, isolate browser state, then enable SSR per route. Never import the singleton demo store into server request handlers. Keep pure static public content prerendered where suitable.
2. **Schema and permissions first.** Version migrations under `supabase/migrations/`. Model profiles, trusted staff capabilities, bookings, original line-item/price snapshots, later service changes, change requests, availability overrides, append-only events, points/inventory ledgers, redemptions and a private notification outbox. Enable RLS and explicit grants on every exposed table/view/function. Authorize own-customer reads and approved staff page/action scopes; deny self-promotion and broad writes to prices, balances and history. Keep private notes in separate protected fields/tables and customer-safe projections.
3. **Verified sessions.** Replace `account.svelte.ts` with the supported Supabase SSR integration (`@supabase/ssr`), request-scoped clients in `src/hooks.server.ts`, and server loaders/actions. Validate identity server-side using the SDK's verified-user/claims guidance; do not authorize from raw `getSession()` data. Configure exact OAuth callback/return-path allowlists and verified account linking. Require MFA for privileged operations. Remove the public Admin/Owner switch from production. Check authorization on every API even if its navigation is hidden.
4. **Atomic booking service.** Replace `store.svelte.ts` calls with validated server actions calling narrowly granted PostgreSQL functions. In one transaction: authenticate/authorize, lock relevant date/resource rows, recheck effective opening hours and capacity (including concurrent blocks), calculate trusted prices/promotions, insert/update booking plus history and outbox. Use unique idempotency keys with actor/payload binding. Preserve the original snapshot and historical prices. Recheck destination capacity on reschedule approval; retain the old booking while the request awaits review, subject to confirming that policy. Failed mutations must not leave success events or emails.
5. **Operations and files.** Migrate points and inventory with ledger entries, balance checks/locks and unique business-event references. Prevent duplicate completion rewards, double redemption and repeat claims. Use private Supabase Storage for forms/photos, server-side content and size validation, short-lived authorized links and retention rules. Never store production photos as localStorage data URLs. No customer payment/downpayment UI is part of this migration.
6. **Email after the transaction.** Configure Brevo custom SMTP in Supabase Auth for confirmation/recovery messages; SMTP credentials are distinct from the application API key. Configure verified senders/domain records, preserve existing mail DNS, disable authentication-link tracking where necessary, and test real confirmation/reset links. For booking updates/reminders, implement `src/lib/server/notifications.ts` and a scheduled outbox worker using Brevo's documented transactional API. The browser never sends email directly or holds the Brevo key.
7. **Delivery worker.** Claim bounded outbox batches using database locks/leases; record attempts, next attempt, provider ID and outcome. Apply timeouts, capped exponential backoff and dead-letter handling. Unique booking-event/template keys prevent duplicate enqueue. Ambiguous provider timeouts still need reconciliation; do not promise exactly-once email. Recheck current appointment/status before reminders. Verify webhooks with the provider-supported mechanism and deduplicate events. An email outage leaves the successful booking intact. Restrict staging recipients and separate marketing consent.
8. **Cutover.** Replace one workflow at a time in staging. Production has one authoritative database: do not fall back to demo seeds/localStorage on API failure. Rehearse import only if there is valid data to preserve. Use compatible expand/migrate/contract migrations, deploy a reviewed release, and rehearse application rollback separately from database disaster recovery.

## Concrete request contract (proposed)

`POST /api/bookings`: accept service/options, contact fields, requested shop-local date/time and idempotency key. Derive account/actor from the verified session. Ignore/reject client totals, discounts, roles, status and audit timestamps. Return the committed booking ID/status and trusted saved estimate, or a clear validation/conflict response. Paginated `GET /api/my-bookings` returns only that account's permitted details. Public availability returns open/full/closed without identities or private notes. Display business timestamps in Asia/Manila; persist server instants as timestamptz.

## Production security and performance gate

- Public Supabase URL/publishable key may be public only with tested RLS/grants. Secret/service-role keys and `BREVO_API_KEY` belong in server-only environment bindings; never `PUBLIC_*`, client imports, logs or git. Prefer scoped user clients for ordinary requests.
- Add exact needed Supabase origins to CSP only when integrated. Deliver CSP as HTTP headers and add `frame-ancestors`, HSTS after HTTPS validation, `X-Content-Type-Options` and appropriate Permissions-Policy. Static meta CSP cannot enforce frame-ancestors. Keep SvelteKit origin/CSRF protections, validate mutation inputs, bound request sizes, and use durable account/IP limits and server-verified bot protection. Direct Supabase access must remain secure independently of the website proxy.
- Use indexed ownership/date/status filters, bounded date ranges and cursor pagination. Return selected fields rather than entire customer/ledger tables. Verify query plans with realistic staging data. Cache only explicitly public results; authenticated responses, refreshed sessions and signed URLs need private/no-store handling. Revalidate availability transactionally regardless of display caching.
- Test two concurrent bookings for the same capacity, duplicate mutation retries, racing date blocks, double redemption, cross-customer reads/writes, restricted staff access and revocation, private-note exclusion, and notification outages. Test direct database/API access, not only UI buttons.
- Keep approved workflows, both themes, reduced motion, keyboard focus, long strings, validation errors and mobile dialogs covered. Add required `npm run check` and build checks to CI; add behavioral/database/browser tests as workflows migrate.
- Agree actual income definitions, staff permission matrix, form/signature content, retention, photo requirements and notification recipients before enforcing new rules.
- Configure redacted monitoring, outbox/backup freshness alerts, managed database backups plus independent encrypted copies, separate storage-object backups, and an isolated restore drill. Document owners and measured recovery results before launch.

## Official integration references checked 2026-11-17

- [Supabase SvelteKit SSR clients](https://supabase.com/docs/guides/auth/server-side/creating-a-client?queryGroups=framework&framework=sveltekit)
- [Supabase row-level security](https://supabase.com/docs/guides/database/postgres/row-level-security)
- [Supabase custom SMTP](https://supabase.com/docs/guides/auth/auth-smtp)
- [Brevo transactional email](https://developers.brevo.com/docs/send-a-transactional-email)

Recheck provider API versions, limits and SDK guidance during implementation. No accounts, infrastructure, migrations or email sends were created in this pass.
