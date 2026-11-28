# F-016: Production hardening, monitoring, analytics and release
> Documented from existing docs on 2026-11-20 — owner to confirm.

**Status:** Blocked (domain, budget, monitoring provider and release checks remain open; account/alert routing recorded in F-027) · **Milestone:** M3 · **Depends on:** all M2 features and required setup evidence

## In one sentence
The single production Worker app is checked locally before release, watched by alerts, measured with consented analytics, and released with a tested recovery procedure.

## User steps (exactly how it works)
1. Run the full suite using local fictional fixtures: phones, accessibility, speed, database races, access revocation and private photos. Separately authorize any production email/data checks.
2. Set up error and uptime checks for the Worker homepage and a Supabase-backed route; alerts go to named people.
3. Enable GA4 (four booking event names, with consent) after the property and consent wording are approved.
4. Review local checks and separately authorized production evidence, confirm release revision and migration order, verify domain and secrets, get written release approval.
5. Deploy, smoke test, confirm staff access, live email, monitoring and backup freshness; agree who decides a rollback.

## Rules and details
- Hosting setup requested for Cloudflare Workers (owner 2026-11-26); service-account ownership and alert delivery setup are specified in [F-027](F-027-service-setup-and-alert-routing.md), not yet applied. Demo retirement follows F-020.
- One production application environment, as directed by owner; local fictional checks and isolated disposable restore verification only. No demo data or browser-local business storage in production.
- Security headers via HTTP: CSP, frame-ancestors, HSTS, nosniff, Permissions-Policy.
- Speed targets (real users, p75): LCP ≤ 2.5s, INP ≤ 200ms, CLS ≤ 0.1, measured on a Philippine network.
- CI runs npm run check, npm test, the Worker build and Worker bundle budgets (static demo retired in F-020).
- A health route reports whether required Supabase settings exist.
- Error/health/recovery recipient confirmed: `elijahpayoc12@gmail.com`; service-account owner: `hercowebsite@gmail.com`. Budget, expected traffic, domain, monitoring provider, release and rollback decisions remain open (Q-17/F-027).
- UI parity decisions must be closed before release (Q-18).

## Screens
- `/privacy-preferences`: analytics consent.

## Data
- None new.

## API
- Health route (path TBD in api-contract).

## Edge cases and errors
- API failure in production → show an error, never fall back to demo data.
- Rollback of the app is rehearsed separately from database disaster recovery.

## Must not break
- Existing live customer/staff workflows; both themes, reduced motion and keyboard focus.

## Acceptance tests (all must pass)
- [ ] Local fictional verification passes, including concurrency and revocation on isolated PostgreSQL; record separately authorized production checks without requiring a standing staging environment.
- [ ] Uptime alert reaches the named recipient.
- [ ] Analytics sends nothing without consent.
- [ ] Production smoke test and rollback rehearsal recorded in the handoff.

## Production security, request limits and performance — 2026-11-27

- Owner confirmed **one production application environment**. Earlier standing-staging requirements are superseded. Perform local fictional regression/security checks and read-only production smoke checks; any hosted data write, load exercise, migration or release needs its relevant explicit authorization. Restore rehearsal uses a disposable isolated target, not a second standing app environment.
- Protect privileged page/data/API/storage access: verified session, enabled membership, required grants and record scope; logged-out access redirects to sign-in or returns a suitable denial without private data. Direct customer/disabled/revoked/unauthorized access fails even when the URL or role is forged. UI hiding is not authorization; retain password-based staff policy.
- Design bounded API abuse controls for login/signup/reset, public availability/catalog, booking/changes, pricing writes, evidence uploads/reads and expensive reports. Specify per-route sustained/burst quotas, IP/account keys, shared persistence/atomic counters, trusted proxy handling, timeouts and cost caps. Block excessive work before expensive database/storage/provider calls; return 429 with retry guidance. Account-only limits cannot cover anonymous abuse; IP-only limits must consider shared networks. Provider/budget/numeric quotas must be documented before implementation, not invented as approved here. Rate limits reduce abuse; they cannot guarantee no attack.
- Preserve existing body/file limits and server input validation, database ownership/RLS/grants, safe caching, CSRF/same-origin checks, secure sessions and upload verification. Test direct Supabase/storage bypass paths too; edge controls alone are insufficient. Add no unlimited retries or error-log floods.
- Performance: paginated lists, debounced searches, cancel stale requests, bounded photo reads, lazy thumbnail loading when proof detail opens, no full-photo gallery fetch on every booking row, no repeated identical API calls or N+1 queries. Cache public catalog/media only with revision/invalidation rules; never shared-cache private evidence/Auth/staff records.
- Validate whole test suite, check, Worker build/budgets, security review and misuse checks. Measure booking/pricing/staff detail and proof on phone/desktop and record limits; retain LCP ≤2.5s, INP ≤200ms and CLS ≤0.1 p75 targets. References checked: OWASP Top 10:2025 (https://top10.owasp.org/), Web Vitals (https://web.dev/articles/vitals).
- Monitor app/API/database readiness, email failures/backlog, upload/storage failures, backup freshness and recovery. F-027 routes grouped failures and recovery notifications to **elijahpayoc12@gmail.com**, independently of booking-email delivery, without credentials/customer/evidence data. Thresholds/provider/budget remain open.
- Acceptance: cross-IP/account bursts and counter races are bounded; abusive requests do not trigger unlimited downstream work; ordinary shared-network users remain usable; auth/grant revocation and direct private reads denied. Booking retries do not duplicate effects. Catalog price changes preserve old records (F-004/F-021). Backup/alert/proof dependencies remain explicit launch checks; passing a build does not prove them operational.

## Ready checklist (no code until all are ticked and the owner approves)
- [x] Every user step is written out
- [ ] Rules, limits and permissions are decided
- [ ] Screens and their states are described
- [ ] Data and API are designed
- [x] Edge cases and "must not break" are listed
- [x] Acceptance tests are written
- [ ] No open questions left
- [ ] **Owner approved:**
