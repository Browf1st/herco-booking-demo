# F-016: Staging hardening, monitoring, analytics and production release
> Documented from existing docs on 2026-11-20 — owner to confirm.

**Status:** Blocked (hosting, domain, alerts and owners not confirmed) · **Milestone:** M3 · **Depends on:** all M2 features

## In one sentence
The Worker app is proven on staging, watched by alerts, measured with consented analytics, and released to production with a tested way back.

## User steps (exactly how it works)
1. Run the full suite on staging: real phones, accessibility, speed, database races, access revocation, private photos, end-to-end email.
2. Set up error and uptime checks for the Worker homepage and a Supabase-backed route; alerts go to named people.
3. Enable GA4 (four booking event names, with consent) after the property and consent wording are approved.
4. Review staging results, confirm release revision and migration order, verify domain and secrets, get written release approval.
5. Deploy, smoke test, confirm staff access, live email, monitoring and backup freshness; agree who decides a rollback.

## Rules and details
- Hosting: Cloudflare Workers proposed, not yet confirmed (Q-17). GitHub Pages demo stays up during staging.
- Separate staging and production environments, projects and secrets. No demo data or browser storage in production.
- Security headers via HTTP: CSP, frame-ancestors, HSTS, nosniff, Permissions-Policy.
- Speed targets (real users, p75): LCP ≤ 2.5s, INP ≤ 200ms, CLS ≤ 0.1, measured on a Philippine network.
- `npm run check` and both builds run in CI.
- A health route reports whether required Supabase settings exist.
- Budget, expected traffic, domain, alert recipients, release and rollback owners: TBD — ask owner (Q-17).
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
- GitHub Pages demo; both themes, reduced motion, keyboard focus.

## Acceptance tests (all must pass)
- [ ] Staging suite passes, including concurrency and revocation tests on hosted PostgreSQL.
- [ ] Uptime alert reaches the named recipient.
- [ ] Analytics sends nothing without consent.
- [ ] Production smoke test and rollback rehearsal recorded in the handoff.

## Ready checklist (no code until all are ticked and the owner approves)
- [x] Every user step is written out
- [ ] Rules, limits and permissions are decided
- [ ] Screens and their states are described
- [ ] Data and API are designed
- [x] Edge cases and "must not break" are listed
- [x] Acceptance tests are written
- [ ] No open questions left
- [ ] **Owner approved:**
