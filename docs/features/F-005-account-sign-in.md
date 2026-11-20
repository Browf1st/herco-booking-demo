# F-005: Customer account and sign-in
> Documented from existing docs on 2026-11-20 — owner to confirm.

**Status:** Testing (Google/Facebook blocked on provider apps) · **Milestone:** M2 · **Depends on:** none

## In one sentence
Customers and staff create a verified account and sign in so bookings, points and staff tools belong to a real, checked person.

## User steps (exactly how it works)
1. Visitor opens `/account` and signs up with email and password.
2. Receives a code by email (6–10 digits) and enters it to verify.
3. Signs in; can reset a forgotten password by emailed code.
4. Optionally signs in with Google or Facebook once each is configured.
5. Customers can save private contact details for future bookings; staff see an Owner/Staff badge and a workspace link.

## Rules and details
- Supabase Auth with server-side checks on every request; never trust browser session data alone.
- Verified email required. Staff: password-only is the approved policy (2026-11-20); MFA is optional and does not gate access (Q-19).
- Demo role switches and fake sign-in are removed from the production app.
- Each social provider stays off until its callback is verified. Linking a social login to an existing email account: TBD — ask owner.
- `HERCO_AUTH_EMAIL_ENABLED` is on only after staging verification.
- Sign-in attempt limits and bot protection: TBD — ask owner.

## Screens
- `/account`: sign up, verify code, sign in, reset password, social buttons, saved contact details, staff workspace link, sign out.
- `/privacy-preferences`: analytics consent.

## Data
- Supabase Auth users; customer profiles.

## API
- Password session route, `/api/auth/callback` for OAuth. Full list TBD in api-contract.

## Edge cases and errors
- Expired or wrong code, expired session, revoked staff grant → next request refused.
- Signed-out visitor on a staff page → sent to Account; customer → My Bookings.

## Must not break
- My Bookings ownership (F-006), staff permissions (F-012).

## Acceptance tests (all must pass)
- [ ] Email sign-up, verify, sign-in, reset work on staging (done once by the maintainer on the hosted project).
- [ ] Cross-device sign-in shows the same bookings.
- [ ] Google and Facebook work per environment once enabled.
- [ ] Unverified account cannot book or reach staff tools.

## Ready checklist (no code until all are ticked and the owner approves)
- [x] Every user step is written out
- [ ] Rules, limits and permissions are decided
- [ ] Screens and their states are described
- [ ] Data and API are designed
- [x] Edge cases and "must not break" are listed
- [x] Acceptance tests are written
- [ ] No open questions left
- [ ] **Owner approved:**
