# F-005: Customer account and sign-in
> Documented from existing docs on 2026-11-20 — owner to confirm.

**Status:** Testing (Google login works locally; Facebook dropped by owner) · **Milestone:** M2 · **Depends on:** none

> 2026-11-20 decision: the owner does not want Facebook login. `HERCO_AUTH_FACEBOOK_ENABLED=false` in `.env.local` and `.dev.vars`, so the button is hidden and the server refuses Facebook sign-in (403). The Supabase Facebook provider stays disabled, and no Meta app was created. The Facebook code path remains, off by default; removing it from the code is a separate change if wanted.

> 2026-11-20 Google: Google Cloud project "HERCO dev" (owner account browf1st1211) with Google Auth Platform in Testing mode, External audience, test users browf1st1211 and elijahpayoc12. Web client "HERCO local" allows origin `http://localhost:5175` and redirect `https://zrwsyezqpizuiiebyssb.supabase.co/auth/v1/callback`. Supabase Google provider is enabled with that client. A full login on `localhost:5175` landed on My Bookings with a valid session. It joined the existing email-password account with the same email and showed its earlier booking, so Supabase's automatic linking of matching verified emails is what currently happens (Q-22). Before launch: publish the app, add branding and a custom auth domain, and add the staging and production origins.

> 2026-11-20: `HERCO_AUTH_GOOGLE_ENABLED` and `HERCO_AUTH_FACEBOOK_ENABLED` are `true` in the gitignored `.env.local` and `.dev.vars`. The "Log in with Google" and "Log in with Facebook" buttons show on `http://localhost:5175/account`. Still pending: the Google and Meta apps, their client ID and secret in Supabase → Authentication → Sign In / Providers. The redirect URL `http://localhost:5175/api/auth/callback` is saved in Supabase → Authentication → URL Configuration. A full social login has not been completed yet.

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

## Account menu (owner-approved 2026-11-23, from the owner's mockup)
- Everyone signed in (staff and customers) gets an **Account** menu at the right of the site header: initials avatar, name, and their email underneath (cut short if long), then "ACCOUNT" with a chevron.
- The menu: their role on top (e.g. Owner, Staff; customers "Customer"), **Account settings** (gear, opens the account page), **Theme** with System / Light / Dark buttons (selected one red), and **Sign out**.
- The theme switch is removed from the footer. Signed-out visitors get a small theme button (sun/moon) in the header instead.
- Closes on Esc, outside click or choosing an item; works with the keyboard; on phones it opens full width under the header. Light and dark themes both blended.
- Both builds get it.

## Screens
- `/account`: sign up, verify code, sign in, reset password, social buttons, saved contact details, staff workspace link, sign out.
- Code step (approved 2026-11-20): "Check your email" card with a mail icon, "We sent a 6-digit code to ja***@example.com", one box per digit (count from `HERCO_AUTH_OTP_LENGTH`, must match Supabase Auth "Email OTP length", default 6). Typing moves to the next box, pasting or phone auto-fill fills all boxes, Backspace goes back. The button stays off until every box is filled. Links: "Resend code" and "Use a different email". Same for the password-reset code.
- Signed-out layout (approved 2026-11-23, option A): one centred card with the HERCO logo, "Welcome back" / "Create your account" and a short line under it, Log in | Sign up tabs (arrow keys work), the social buttons (unchanged), an "or use your email" divider, then the email form shown straight away (no extra "Log in with Email" click). Labels above inputs, a show/hide password button, "Forgot password?" beside the Password label, sign-up shows "At least 8 characters", one red main button. Error and info messages show inside the card. Reset-password and code steps use the same card with "Back to log in". Shared parts: `AuthShell`, `PasswordField` (also used by the demo account screen).
- Signed-in layout (approved 2026-11-20): initial avatar, "Account" title and email at top; then cards for Profile, Staff access (staff only), Appearance (System / Light / Dark, the same setting as the header menu), and Sign out on its own row at the bottom.
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
- [ ] Google and Facebook work per environment once enabled. (Google passed locally on 2026-11-20; Facebook dropped by the owner; staging and production not yet.)
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
