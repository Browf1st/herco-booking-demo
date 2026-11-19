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
- The schedule still uses the generic Unavailable label for elapsed same-day hours. The production availability milestone includes consistent Past slot labels and controls across both admin views.
- Supabase project bindings, Brevo credentials, and live release configuration have not been verified. The GitHub Pages workflow remains the demo deployment. No production migration or release has been performed.

## Next safe increment

### Booking history update — 2026-11-17

Added a consolidated Date filter dropdown (Today by default, This month, Specific date, Custom range, All dates), using appointment dates in Philippine time. This month includes the entire calendar month. Added clickable total/Pending/Booked/Completed/Cancelled counts, an All statuses filter, and 10-booking pagination with result ranges. Counts follow the date/search filters; status selection narrows the records. Filter changes reset to page one, with invalid-range and empty-result feedback.

Refined the Booking History UI: compact summary cards with selected-state checks, one grouped search/date/status panel, separate customer and appointment columns, responsive record rows, and an empty-state View all bookings shortcut. Inspected desktop/mobile renders and checked both themes at 320/390/768/1440px without horizontal overflow. Pagination, filters, expanding details, empty-state recovery and reset passed isolated browser checks with no page errors.

Verified Svelte check (0 errors/warnings), production build, and diff whitespace. Isolated Edge tests with fictional fixtures passed Manila-versus-US date boundaries, full-month and inclusive-range boundaries, all date modes, invalid ranges, status cards/dropdown, totals, search, empty results, and pagination/reset behavior. Layout checked at 320/390/768/1440px without horizontal overflow; mobile screenshot inspected. No remote access or deployment for this update.

Confirm hosting/budget and the permission matrix, then introduce isolated Supabase staging migrations and direct policy/concurrency tests. Replace one booking workflow with verified server actions, RLS and transactional outbox before adding Brevo delivery. Keep demo storage out of server request state. Review staging on real mobile devices with representative customers/staff, capture throttled production performance traces, test recovery and get approval for the concrete release before launch.

Known remaining limitations: browser storage is untrusted, full/corrupt booking or operations blobs still need a recovery/export design, no real authentication or cross-device transactions, no private file storage, no outbox/worker, and no server-enforced permissions. Meta CSP cannot implement framing protection; that needs production HTTP headers. Real-device, cross-browser, accessibility and load tests remain launch work.

### Staff Access production transition

- Use the page and action IDs in `src/lib/staffAccess.svelte.ts` as the starting permission matrix. The demo's Admin and Owner view links select mock roles, and Owner → Staff Access previews a configured account. Remove these mock role switches and browser account records during the production migration. Create a separate staging database with fictional accounts for workflow tests.
- Invite staff through verified Auth identities and link each identity to a shop membership. Store role, active status, page grants, and action grants in the database. Provision the first Owner through a trusted administrative process. Authorize Owner management against the target shop and allow those actions only for Admin and Staff memberships. Record invitation, permission changes, and disabling in an audit trail with the actor, target, timestamp, and changed grants.
- In every server load and mutation, resolve the authenticated actor and current shop membership, check that it is active, then enforce the relevant page and action grants together. Use row-level policies for shop and record access. Project fields before returning data so staff with Reports access alone do not receive final charges in report rows, booking activity, or exports. Preserve the customer booking path and check verified booking ownership independently.
- Recheck membership and permissions during each write so a revoked grant takes effect on the next request, including a previously opened form. Commit each mutation and audit entry together. Verify allowed and denied direct requests for page-only staff, individual action grants, disabled accounts, cross-shop targets, and attempted role escalation. Capture those tests before replacing the demo switcher.

### Booking completion evidence

Require at least one photo for each new completion. The demo accepts up to three camera or album photos and stores compressed previews in browser storage. In production, validate uploaded media and check for an attached private photo that belongs to the booking before committing the completion and its audit entry. Preserve historical completed bookings that predate the requirement.

Block completion while any saved service line still needs a shop quote or has a price range. Save an exact amount for each unresolved line through the service editor. Fixed-price lines need no extra confirmation. Check the current booking lines again inside the production completion transaction.
