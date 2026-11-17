# Performance, security and Supabase/Brevo implementation

Updated 2026-11-17. This is an implementation guide, not a deployed backend.

## Current boundary

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
