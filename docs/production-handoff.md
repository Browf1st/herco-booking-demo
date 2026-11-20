# HERCO handoff — 2026-11-17

See [production-plan.md](production-plan.md) for the current implementation boundary, Supabase/Brevo sequence, source references and asset measurements. Existing workflow coverage remains in [requirements-coverage.md](requirements-coverage.md).

## Completed locally

Optimized gallery delivery, cached points aggregation, account restoration guards, static production CSP, referrer policy, responsive form/card constraints, theme-aware browser color and keyboard/reduced-motion improvements. Added migration comments at the demo account, store, operations and admin-navigation boundaries. CI now runs the existing Svelte/type check before building.

No dependency changes, remote requests to Git/PR hosts, commits, deployment, provider provisioning, database migration or email sends. Pre-existing untracked `.vs/` was left alone. The demo's openly accessible Admin/Owner behavior remains a simulation, not production authorization.

## Verification

- Svelte sync/check: 0 errors and 0 warnings before and after changes. Production build passes; `git diff --check` passes.
- Local headless Edge: home, book, account, points, Showcase and admin at 320/390/768/1440px in both themes (48 combinations), after waiting for actual application content: no page errors or viewport-wide overflow. Inventory also checked at 320px. This is a smoke matrix, not full workflow/assistive-technology coverage.
- Mobile navigation to Showcase, comparison slider movement, explicit light theme through reload and dark-theme browser color; corrupt account JSON and invalid saved booking-ID shape followed by demo sign-in and reload all passed.
- All homepage lazy images loaded successfully after scrolling; inspected mobile home and desktop booking/mobile inventory screenshots. Ghost-button dark background/text verified as rgb(36,45,58) / rgb(240,243,248) after the theme transition settled.
- Generated CSP inspected and a deliberately injected inline script was blocked. Normal route navigation and theme script worked without CSP errors.
- A separate `BASE_PATH=/Herco` build passed; all ten homepage images loaded, Showcase navigation/comparison worked under `/Herco/preview`, and the browser color was `#11151c` in dark mode, with no failed responses or page errors. Restored the ordinary root-path build afterward.
- Image measurement: initial mobile image bytes 2,808,480 → 381,846 under the same local unthrottled 390×844 / DPR 1 conditions. No field-performance or production authorization claims.

`npm` was absent from this shell's PATH, so checks used `node node_modules/@sveltejs/kit/svelte-kit.js sync`, `node node_modules/svelte-check/bin/svelte-check --tsconfig ./tsconfig.json` and `node node_modules/vite/bin/vite.js build`, equivalent to the repository scripts. Browser checks used bundled Playwright with the installed Edge executable and isolated test contexts containing fictional data.

## Production migration status

The [production roadmap](production-plan.md#production-implementation-checklist) is the ordered implementation checklist. The [configuration checklist](production-plan.md#configuration-you-can-do-in-parallel) lists resources that can be prepared alongside development.

- The customer booking card changes are local working-tree edits at the time of this handoff. Request controls are in the header. The collapsed card shows the booking overview and View details expands the record inline. The Svelte check and build passed for these edits.
- The demo schedule and Manage Availability now show Past slot for elapsed same-day hours. The server migration includes shared atomic date and slot controls. The admin UI still needs to call them.
- Supabase project bindings, Brevo credentials, and live release configuration have not been verified. The GitHub Pages workflow remains the demo deployment. No production migration or release has been performed.

### Backend increment on main

- Added the first versioned Supabase migration and server endpoints for catalog, availability, signed-in booking submission, paginated personal booking reads, and password sessions. The API uses a request-scoped session and requires explicit Supabase bindings.
- The Worker build reads business data from Supabase. The GitHub Pages build continues to use demo screens and data. Build the Worker with `npm run build:worker` and run it locally with `npx wrangler dev`. Add site bindings via `.dev.vars` locally or Worker environment settings in staging. The example env file lists placeholders.
- Local checks passed for Svelte diagnostics, both builds, and the Worker browser flow at mobile width with mocked APIs. The browser check covered the sign-in gate, login, booking retry with the same request ID, confirmation, My Bookings after reload, and no business records in localStorage. Live Supabase sign-in and cross-device persistence still need verification.
- Account now supports configurable email signup, verification, password recovery, Google/Facebook sign-in, and staff authenticator enrollment. The existing password session route remains available for accounts provisioned in Supabase.
- The staff workspace now supports date/slot controls, booking confirmation, customer change requests, scheduled bookings for verified customers, staff grants, points and rewards, inventory, pricing and one active promotion, private completion photos, and aggregate booking reports. Database transactions protect repeat requests and capture staff actions.
- The separate [email worker](email-worker.md) sends booking receipts, confirmations, and change decisions. Reminders are optional and recheck the appointment immediately before sending.
- Customers can withdraw pending requests without changing their visit and save private contact details for future bookings. Staff can cancel or reschedule directly with separate grants, search the scoped customer directory, and open [a configured walk-in form](walk-in-intake.md) for the verified owner of an existing scheduled booking.
- Signed-in customers can now submit today's walk-in from Book, sign the active versioned form, and enter the normal staff queue without taking a scheduled slot. The booking is linked to the verified account immediately.
- Optional booking analytics collect four event names with consent and a random browser identifier. The site health route reports whether required Supabase settings are present. External uptime checks, alert delivery, and operational ownership still need configuration.
- Staff pricing now accepts fixed prices, ranges, and shop quotes. Authorized staff can save an exact line price at any booking stage. A post-completion correction updates the report by the difference and preserves the original completion amount. Date-based reports include a separate net-corrections figure.
- Scheduled and walk-in customer bookings save the ceramic finish, powder parts and wheel dimensions. The booking form shows a server estimate for the selected bike and options before submission. If a rule, base rate, or promotion changes the estimate, the customer reviews the refreshed amount before trying again. Already saved bookings retain the original estimate.
- In **Staff workspace → Pricing → Coating price rules**, authorized staff can add, edit, enable, and disable fixed-price, range, or quote-required rules. New rules default to disabled. Exact bike rules take priority over general rules with the same options. Each save records the acting staff member and the before-and-after settings.
- Stock on hand and movement history can be downloaded as permission-checked CSV files. The movement export defaults to the last 30 days and accepts up to 366 days per export, with a 10,000-row cap.
- Test the complete workflow with a configured staging project and fictional accounts/catalog first. Leave demo fixtures out of production server paths.

### Configuration before live staging tests

1. Set `PUBLIC_SUPABASE_URL` and `PUBLIC_SUPABASE_PUBLISHABLE_KEY` from the private dev inventory. Apply the versioned migrations in order to the isolated staging database. Use the [staff bootstrap instructions](staff-access.md) for the first Owner and assign only the grants needed by each staff account. Create fictional customers and enable a test catalog with approved or test-only prices.
2. To enable email signup and password recovery, configure Brevo SMTP in Supabase, enable email confirmation, and make the signup and recovery templates include `{{ .Token }}`. Turn on `HERCO_AUTH_EMAIL_ENABLED` only after staging verification. For OAuth, enable each configured provider, allowlist the site's `/api/auth/callback` URL in Supabase, and configure the provider's callback at the Supabase project URL before enabling its named flag.
3. Create a private Storage bucket named `herco-completion`. Limit it to JPEG, PNG, and WebP and 4 MB per object. Grant no browser upload or read access. Configure `HERCO_STORAGE_SECRET_KEY` in the site Worker's secrets so the server can upload and read evidence after checking staff permissions. Approve a retention policy and cover abandoned uploads and saved evidence in backup and cleanup procedures.
4. Configure the [separate email worker](email-worker.md) with staging-only credentials and the test recipient allowlist. Test login mail and transactional mail separately. Leave reminder timing disabled until approved.
5. Enable `HERCO_GA4_MEASUREMENT_ID` and `HERCO_GA4_API_SECRET` only after choosing the correct property and approving consent copy. Configure external checks for the Worker homepage and a small Supabase-backed route, direct alerts to the named recipients, and rehearse database and Storage restore before release.

### Pending implementation

- [ ] Populate the approved bike and dimension price matrix in Staff Pricing. Verify the live estimate, booking snapshot, and price correction workflows against the staging database before release.
- Change requests stay open for manual handling. The staff queue, customer withdrawal, decision notifications, and optional email to the configured shop inbox are implemented.
- Inventory supports optional supplier, storage location, unit cost, billing rate, and storage capacity. HERCO Points remain manually awarded and corrected as agreed.
- [ ] Configure and verify the [photo cleanup and recovery tools](recovery.md), backup jobs, and operational alerts once the storage destinations, retention, and recovery targets are chosen. Rehearse restoration in staging.
- [ ] Verify the live staging workflows with isolated Supabase, Storage, Brevo, MFA, and enabled OAuth providers. Run concurrent booking and points tests against hosted PostgreSQL before release.

### Engineering checks

Codex and Claude share [the repository guide](../AGENTS.md) and [the OWASP and performance checks](engineering-checks.md). The engineering workflow checks dependency advisories, Worker HTTP controls, static and Worker bundle budgets, and the migration chain with synthetic database roles. Production and staging provider setup remain separate.

The Worker limits JSON payloads, blocks framing, and guards private API responses against shared caching. The database blocks direct browser access to completion objects and requires private bucket settings for authorized uploads and reads. Completion-only staff can record the finalized service total. A different final charge requires the price adjustment grant.

### Values to supply for this increment

- **Coating catalog** — approved service codes and labels, fixed prices or range endpoints, quote-required services, exact bike model names, and finish, part and dimension combinations. Enter base rates and option-specific rules in **Staff workspace → Pricing**. A blank bike name allows any eligible bike to match the exact selected options. With no enabled rule, the estimate uses the base rate. A quote-required base service lets the shop price unmatched configurations individually.
- **Walk-in form** — approved title, full text, version, approving staff identity, and confirmation that the typed-name acknowledgement is acceptable. Configure it per [walk-in intake setup](walk-in-intake.md).
- **Shop inbox and test recipients** — approved operational inbox for change requests, staging allowlist, and Brevo sender and server credentials. Configure per [email worker setup](email-worker.md). The inbox is empty by default.
- **Photo cleanup** — target Supabase project, cleanup Worker credential, and approved age for unlinked uploads. Cleanup starts disabled. Configure per [recovery setup](recovery.md).
- **Backup and alert operations** — approved schedule and retention, source and isolated restore project access, independent encrypted storage, runner and encryption key, alert destination, and acceptable data loss and downtime. Configure these outside Git before a restore drill.

## Next safe increment

### Booking history update — 2026-11-17

Added a consolidated Date filter dropdown (Today by default, This month, Specific date, Custom range, All dates), using appointment dates in Philippine time. This month includes the entire calendar month. Added clickable total/Pending/Booked/Completed/Cancelled counts, an All statuses filter, and 10-booking pagination with result ranges. Counts follow the date/search filters; status selection narrows the records. Filter changes reset to page one, with invalid-range and empty-result feedback.

Refined the Booking History UI: compact summary cards with selected-state checks, one grouped search/date/status panel, separate customer and appointment columns, responsive record rows, and an empty-state View all bookings shortcut. Inspected desktop/mobile renders and checked both themes at 320/390/768/1440px without horizontal overflow. Pagination, filters, expanding details, empty-state recovery and reset passed isolated browser checks with no page errors.

Verified Svelte check (0 errors/warnings), production build, and diff whitespace. Isolated Edge tests with fictional fixtures passed Manila-versus-US date boundaries, full-month and inclusive-range boundaries, all date modes, invalid ranges, status cards/dropdown, totals, search, empty results, and pagination/reset behavior. Layout checked at 320/390/768/1440px without horizontal overflow; mobile screenshot inspected. No remote access or deployment for this update.

Confirm hosting/budget and the permission matrix, then introduce isolated Supabase staging migrations and direct policy/concurrency tests. Replace one booking workflow with verified server actions, RLS and transactional outbox before adding Brevo delivery. Keep demo storage out of server request state. Review staging on real mobile devices with representative customers/staff, capture throttled production performance traces, test recovery and get approval for the concrete release before launch.

Known remaining limitations: browser storage is untrusted, full/corrupt booking or operations blobs still need a recovery/export design, no real authentication or cross-device transactions, no private file storage, no outbox/worker, and no server-enforced permissions. Meta CSP cannot implement framing protection; that needs production HTTP headers. Real-device, cross-browser, accessibility and load tests remain launch work.

### Staff Access production transition

- Use the page and action IDs in `src/lib/demo/staffAccess.svelte.ts` as the starting permission matrix. The demo's Admin and Owner view links select mock roles, and Owner → Staff Access previews a configured account. Remove these mock role switches and browser account records during the production migration. Create a separate staging database with fictional accounts for workflow tests.
- Invite staff through verified Auth identities and link each identity to a shop membership. Store role, active status, page grants, and action grants in the database. Provision the first Owner through a trusted administrative process. Authorize Owner management against the target shop and allow those actions only for Admin and Staff memberships. Record invitation, permission changes, and disabling in an audit trail with the actor, target, timestamp, and changed grants.
- In every server load and mutation, resolve the authenticated actor and current shop membership, check that it is active, then enforce the relevant page and action grants together. Use row-level policies for shop and record access. Project fields before returning data so staff with Reports access alone do not receive final charges in report rows, booking activity, or exports. Preserve the customer booking path and check verified booking ownership independently.
- Recheck membership and permissions during each write so a revoked grant takes effect on the next request, including a previously opened form. Commit each mutation and audit entry together. Verify allowed and denied direct requests for page-only staff, individual action grants, disabled accounts, cross-shop targets, and attempted role escalation. Capture those tests before replacing the demo switcher.

### Booking completion evidence

Require at least one photo for each new completion. The demo accepts up to three camera or album photos and stores compressed previews in browser storage. In production, validate uploaded media and check for an attached private photo that belongs to the booking before committing the completion and its audit entry. Preserve historical completed bookings that predate the requirement.

Block completion while any saved service line still needs a shop quote or has a price range. Save an exact amount for each unresolved line through the service editor. Fixed-price lines need no extra confirmation. Check the current booking lines again inside the production completion transaction.

## Hosted backend testing setup — 2026-11-20

- With maintainer approval, applied all 31 repository migrations in order to Supabase project `zrwsyezqpizuiiebyssb`. Preflight found no HERCO schema or tables. Applied as one transaction using the authenticated Dashboard SQL editor because the direct database hostname was not reachable locally.
- Recorded all 31 versions, names and original SQL statements in `supabase_migrations.schema_migrations` and reloaded the Data API schema cache.
- Hosted verification: 31 migration records; zero public HERCO tables missing row-level security; anonymous booking reads denied; authenticated SELECT privilege present. The signed-in local My Bookings screen now loads its empty state successfully.
- Brevo SMTP was saved by the maintainer. Signup and recovery email templates use the full verification token. Email confirmation and signup are enabled; local email-auth bindings are enabled in ignored files. The maintainer received confirmation mail and signed in. Email codes accept 6–10 digits to match provider configuration; authenticator MFA remains six digits.
- This is backend testing setup, not a production release. Staff bootstrap/MFA, approved catalog prices, private completion bucket, transactional email worker and remaining release/recovery checks still require setup or verification. No role grants or real service prices were invented during migration installation.

### First Owner bootstrap — 2026-11-20

Following explicit maintainer approval in this session, the authenticated Supabase Dashboard administrator applied the guarded bootstrap from `docs/staff-access.md` to the maintainer-confirmed verified account. Confirmed enabled Owner membership with 10 page grants and 19 action grants. No existing Owner was overwritten. The local Account page recognizes staff eligibility and offers authenticator enrollment; MFA remains required and enrollment is left to the account owner. The exact approved identity is retained in the private setup record rather than this repository document.

### Password-only staff policy — 2026-11-20

The maintainer explicitly approved email-and-password staff access in every environment, including production. This supersedes earlier mandatory staff-MFA instructions in this handoff. Verified email, enabled database membership, page/action grants, ownership, and private evidence restrictions remain required. Existing optional MFA endpoints do not gate staff access.

Applied migration `202611190032_password_staff_access.sql` to the confirmed hosted project after action-time confirmation and recorded the original statement in migration history. The migration replaces 15 current function definitions with checks for verified, enabled staff and returns the trusted role with workspace permissions. Account now displays Owner/Staff access and a workspace link rather than authenticator enrollment. Removed mandatory MFA checks from booking/manual-booking routes and obsolete UI verification states.

Verification: zero Svelte/type errors or warnings; static and Worker builds passed; seven HTTP hardening tests passed. Hosted rollback-only assertions confirmed the actual Owner can obtain permissions using AAL1 and a non-staff identity cannot obtain workspace permissions or reports. The signed-in Owner opened the local staff workspace, with schedule, pricing, inventory, reporting and staff-management navigation visible. Updated isolated database assertions also cover unverified and disabled members, but the full SQL fixture suite was not run locally because PostgreSQL tooling is unavailable. No production hosting deployment or Git commit/push performed.

### UI parity audit — 2026-11-20

Maintainer rejected the simplified Worker presentation and requested a complete comparison before corrections. Produced `docs/ui-parity-audit.md` with 89 comparison units across all customer and staff UI areas plus `docs/ui-parity-file-inventory.txt`. Confirmed preserved demo copies and shared global styling, and traced the main drift to separately rendered Server components. Browser comparison confirmed the demo calendar/tiles/modal layout versus the simplified Worker cards. Audit-only after this instruction; no further UI correction performed. The recent role navigation work remains in the uncommitted working tree; Owner redirect to Reports and permitted staff main navigation were observed, but fresh password-login routing still needs end-to-end validation. Questions about navigation grouping, modal interactions and customer-visible/data-model differences remain open.

### UI parity continuation — 2026-11-20 (Claude)

- Finished the screens left generic: Customers now uses the demo's expandable records (total, live search, mobile/email/points, booking history) and Activity log uses the demo's module filter, search and labeled entries. The date range stays because the server caps queries at 31 days.
- Staff header now uses the demo admin tab styling. The Booking menu shows pending booking and change-request counters (`herco_staff_pending_counts`, `/api/staff/counts`) and offers Manual booking Online and Walk-in. The Owner order follows the demo: Reports, Accounts, Activity Log, More.
- Signed-out visitors to staff pages go to Account. Signed-in customers go to My Bookings, and staff without a section grant go to their landing page.
- Fixed migration 035 (`herco_inventory_options_write` did not compile) and the missing `search` icon type error. Removed the maintainer's email from the UI seed, which now uses the enabled Owner.
- Verified with Svelte check (0/0), 11 node tests, both builds and budgets (Worker budgets raised for the demo UI), and the full migration chain plus `security`, `customer-rewards` and `operations-ui` assertions in PGlite. Browser checks used stubbed staff responses because no staff session was available.
- With maintainer approval, applied migrations 033–036 to the hosted project through the Dashboard SQL editor. Each script was checked by SHA-256 against the repository file and recorded in `supabase_migrations.schema_migrations`, giving 36 records. Applied `supabase/seeds/ui-parity-test.sql` after fixing the walk-in fixture's missing `booking_kind`. The first attempt rolled back with no rows written. The seed created 3 non-login TEST customers, 8 TEST bookings, 3 TEST rewards, 3 TEST stock items, the demo test price table, the TEST-labelled ceramic and powder services, and the `TEST-UI-v1` walk-in form. All TEST records are removable by the `f17e0000-` id prefix.
