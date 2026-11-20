# HERCO API contract

The only thing screen code needs to know about the server. Update this first when an endpoint changes.

- **Base path:** `/api` (SvelteKit `+server.ts` routes in `src/routes/api/**`). Everything is dynamic (`prerender = false`).
- **Auth:** Supabase Auth session stored in HTTP-only, `SameSite=Lax` cookies (`Secure` on https). Created by `POST /api/auth/session` (or the social/email flows below), cleared by `DELETE /api/auth/session`. The browser sends the cookie automatically; there is no bearer token. Every database call runs as the signed-in user, so Supabase policies and database functions (RPCs) make the final permission decision. Where this doc says "staff with grant X", the grant is enforced inside the database function, not in the route (the route only reports `403` when the database says no).
- **Same-origin rule:** every `POST`, `PUT`, `PATCH` and `DELETE` (except where noted) must send an `Origin` header equal to the site origin, otherwise `403 "Submit this request from HERCO."`. Browsers do this automatically for same-site fetches.
- **Error shape:** `{ "message": "<human text>" }` with the HTTP status (SvelteKit `error()`). Whether the body is JSON depends on the request `Accept` header (send `Accept: application/json`) (unclear from code). Two endpoints add a machine code: see `ErrorWithCode` in Shared types.
- **Common status codes:** `400` invalid input; `401` not signed in; `403` signed in but not allowed (or same-origin check failed); `404` not found or not visible to you; `409` conflict / stale revision / slot taken / price changed; `413` JSON body too large; `429` too many attempts (passed through from Supabase Auth only; the app has no rate limiter of its own); `503` backend or dependency unavailable or not configured (never leaks internals).
- **JSON body limit:** 32 KiB (`413 "This request is too large."`). Checked from `Content-Length` and while streaming. Malformed or non-UTF-8 JSON is read as empty, so the endpoint returns its normal `400`. Exceptions: `PUT /api/completion` (raw photo, 4 MB) and `/api/analytics` (plain text, 64 bytes).
- **Caching / headers:** `/api/**` error responses and any response that sets a cookie are forced to `Cache-Control: private, no-store`; API responses with no cache header also get it. All responses carry `X-Frame-Options: DENY`, `frame-ancestors 'none'`, `X-Content-Type-Options: nosniff`.
- **Idempotency:** most write endpoints take a client-generated `requestId` (UUID). Re-sending the same `requestId` is how the client safely retries after a `503`. The route only validates the UUID format; replay behaviour lives in the database function (unclear from code).
- **IDs/dates:** `uuid` means a 36-character hex UUID. `date` means `YYYY-MM-DD`. Money is whole centavos (integers). Hours are integers `9` to `16` where validated.
- **Pagination:** `page` is 1-based; page size is 20 in the routes that paginate.

Auth levels used below: **public** (no sign-in check in the route; the database may still limit what it returns), **signed-in** (route checks for a Supabase user, `401` if none), **verified customer** (signed in with a confirmed email; enforced by the database, reported as `403`), **staff + grant** (database-enforced, reported as `403`).

---

## Auth & account

### `GET /api/auth/session`
- **Who:** signed-in.
- **Input:** none.
- **Success:** `200` `{ id: uuid, email: string }`.
- **Errors:** `401` not signed in; `503` auth service down.

### `POST /api/auth/session`
- **Who:** public (this is sign-in). Same-origin required.
- **Input (JSON):** `email` string, trimmed, 1-254 chars, required; `password` string, 1-1024 chars, required.
- **Success:** `200` `{ id: uuid, redirectTo: string }` and sets the session cookie. `redirectTo` is the landing page for the account (customer or staff workspace, computed from the user's permissions).
- **Errors:** `400` missing or out-of-range email/password; `401` wrong credentials (generic message); `403` `{ code: "email_confirmation_required", message }` email not confirmed; `429` too many attempts (from Supabase); `503` service down or navigation could not be loaded.

### `DELETE /api/auth/session`
- **Who:** public (no sign-in check; clears this browser's session). Same-origin required.
- **Input:** none.
- **Success:** `204` no body, cookie cleared (this device only, `scope: local`).
- **Errors:** `503` sign-out failed.

### `GET /api/auth/account`
- **Who:** public.
- **Input:** none.
- **Success:** `200` `{ email: boolean, providers: { google: boolean, facebook: boolean }, otpLength: number }` showing which sign-in options are switched on. `otpLength` (added 2026-11-20) is the number of digits in emailed codes (6-10, from `HERCO_AUTH_OTP_LENGTH`, default 6); the screen shows one box per digit. `Cache-Control: no-store`.
- **Errors:** none.

### `POST /api/auth/account`
- **Who:** public. Same-origin required. Body field `action` selects the operation. Anything other than `oauth` returns `403 "Email account setup is unavailable."` when email auth is switched off.
- **Input (JSON):**
  - `{ action: "oauth", provider: "google" | "facebook" }` returns `200 { url: string }`: the provider page to send the browser to (callback is `/api/auth/callback`).
  - `{ action: "signup", email, password, name }`: `email` valid address up to 254 chars; `password` 8-1024 chars; `name` 1-120 chars. Returns `202 { accepted: true }` whether or not the email already exists (does not reveal registered emails). Fails with `503` if the auth provider would log the user in without email confirmation.
  - `{ action: "recover", email }`: returns `202 { accepted: true }` (always, if the email is well-formed).
  - `{ action: "resend", email }` (added 2026-11-20): sends a new signup confirmation code. Returns `202 { accepted: true }` (always, if the email is well-formed; does not reveal registered emails). Supabase rate limits apply (`429`).
  - `{ action: "confirm", email, token }`: `token` is a 6-10 digit emailed code. Returns `200 { redirectTo: string }` and signs the user in.
  - `{ action: "reset-password", email, token, password }`: same as confirm plus a new password (8-1024 chars). Returns `200 { redirectTo: string }` and signs the user in.
- **Errors:** `400` invalid field, weak password, wrong or expired code, unknown `action` ("Choose an account action."); `403` provider or email auth disabled; `429` too many requests; `503` account service unavailable.

### `GET /api/auth/callback`
- **Who:** public. Browser redirect target for social sign-in, not called by screen code directly. No same-origin check.
- **Input (query):** `code` string up to 1024 chars (set by the provider); `error` (if present, treated as failure).
- **Success:** `303` redirect to the account landing page (customer or staff workspace). Sets session cookie, `Referrer-Policy: no-referrer`.
- **Errors:** `303` redirect to `/account?auth=retry` when `code` is missing, too long, `error` is present, or the exchange fails. `503` if navigation could not be loaded after sign-in.

### `GET /api/auth/contact`
- **Who:** signed-in.
- **Input:** none.
- **Success:** `200` `{ name: string, mobile: string, email: string, provider: string, leaderboardOptIn: boolean, leaderboardAlias: string }`. `name` falls back to the signup name when no profile row exists.
- **Errors:** `401`; `503`.

### `PUT /api/auth/contact`
- **Who:** signed-in. Same-origin required.
- **Input (JSON):** `name` string, up to 120, required; `mobile` string, required (may be empty), else 7-15 digits with optional `+`, spaces, `()` and `-`; `leaderboardOptIn` boolean (anything but `true` is false); `leaderboardAlias` string up to 40 (required non-empty when opted in).
- **Success:** `200` `{ name, mobile, leaderboardOptIn, leaderboardAlias }` (trimmed values as saved).
- **Errors:** `400` invalid field; `401`; `503`.

### `GET /api/auth/mfa`
- **Who:** signed-in. Reports whether the user is a verified-email staff account that may enroll an authenticator.
- **Input:** none.
- **Success:** `200` `{ staff: false }` for non-staff, otherwise `{ staff: true, verified: boolean, needsExistingVerification: boolean, factors: [{ id: string, name: string }] }`. `verified` is true when the session is at assurance level 2; `factors` lists verified TOTP factors only.
- **Errors:** `401`; `503`.

### `POST /api/auth/mfa`
- **Who:** staff (database says the user may enroll MFA) with a confirmed email. Same-origin required.
- **Input (JSON):**
  - `{ action: "enroll" }` starts authenticator setup and removes any abandoned unverified factor first. Returns `200 { factorId: string, qrCode: string (SVG data URI), secret: string }`.
  - `{ action: "confirm-enrollment", factorId: string, code: "dddddd" }` verifies the 6-digit code for an unverified factor. Returns `204`.
- **Errors:** `400` bad code, unknown factor, rejected code, or unknown action; `401`; `403` not a verified staff account; `409` enroll while a verified factor exists ("Verify with your existing authenticator."); `429`; `503`.

---

## Availability & catalog

### `GET /api/availability`
- **Who:** public (no sign-in check in the route; the database function decides what is returned).
- **Input (query):** `from` date, `to` date, both required.
- **Success:** `200` availability data from the database for the range (shape unclear from code; see Shared types `Availability`).
- **Errors:** `400` missing or badly formatted dates, or range rejected ("up to 42 days within the booking calendar"); `503`.

### `GET /api/catalog`
- **Who:** public (no sign-in check in the route).
- **Input:** none.
- **Success:** `200` service catalog JSON (shape unclear from code).
- **Errors:** `503`.

### `GET /api/booking-catalog`
- **Who:** verified customer (database returns permission error otherwise).
- **Input:** none.
- **Success:** `200` booking-screen catalog JSON (shape unclear from code).
- **Errors:** `403` "Sign in with a verified account."; `503`.

### `POST /api/coating-estimate`
- **Who:** verified customer (route has no explicit sign-in check; database reports `403`). Same-origin required.
- **Input (JSON):** `bike` string, trimmed, 1-120, required; `services` array of 1-20 strings (each 1-64 chars), required; `coating` optional object (JSON length under 3000 chars; not an array).
- **Success:** `200` price preview from the database (shape unclear from code; fields used elsewhere include a price fingerprint, see Shared types `PriceFingerprint`).
- **Errors:** `400` invalid input, or the database rejected the configuration (message passed through); `403` "Verify your email before preparing a booking."; `503`.

---

## Bookings (customer)

### `GET /api/bookings`
- **Who:** signed-in. Returns only the caller's own bookings (filtered by their user id).
- **Input (query):** `page` integer 1-500, default 1 (page size 20).
- **Success:** `200` `{ bookings: Booking[], hasMore: boolean }`. Each booking adds `approved_at`, `completed_at`, `cancelled_at` (ISO timestamps or `null`). Newest first.
- **Errors:** `400` bad page; `401`; `503`.

### `POST /api/bookings`
- **Who:** verified customer (route checks signed in; database reports `403` for unverified). Same-origin required.
- **Input (JSON):** `requestId` string (retry key); `date` string; `hour` integer; `services` array of 1-20 strings (each up to 64); `bike` string; `name` string; `phone` string (may be empty: the mobile number is optional for a customer's own online booking; if not empty, the route requires 7-15 digits with only `+`, spaces, `()` and `-`, same rule as `/api/auth/contact`, else `400 "Enter a valid mobile number, or leave it blank."`; the database also caps it at 40 characters); `plate` optional string; `coating` optional object (under 3000 chars JSON); `priceFingerprint` optional 32 lowercase-hex string. Lengths of `bike`, `name`, `phone`, `plate` and the date/hour ranges are not checked in the route (database decides, unclear from code).
- **Success:** `200` `{ id: uuid, status: string, totalCentavos: number, estimateOpen: boolean }`. `estimateOpen` is true when any service needs a quote or has a price range.
- **Errors:** `400` invalid input; `401`; `403` verify your email; `409` slot unavailable, or `{ code: "price_changed", message }` when prices changed since the estimate; `503` retry using the same `requestId`.

### `GET /api/booking-prices`
- **Who:** route has no sign-in check; the database function returns `42501` (shown as `403`) if you may not see the booking (unclear from code who may read).
- **Input (query):** `booking` uuid, required.
- **Success:** `200` price lines for the booking (shape unclear from code).
- **Errors:** `400` bad id; `403` "Price corrections require staff permission."; `404` booking not found; `409`; `503`.

### `POST /api/booking-prices`
- **Who:** staff with price-adjustment permission (database-enforced). Same-origin required. Route has no sign-in check of its own.
- **Input (JSON):** `booking` uuid; `requestId` uuid; `revision` integer >= 0; `service` string 1-100; `centavos` safe integer 0 to 99,999,999,999; `reason` string, 1-300 after trim.
- **Success:** `200` updated price data from the database (shape unclear from code).
- **Errors:** `400` invalid input or database rejected it; `403` no permission; `404` booking not found; `409` stale revision or check constraint (message passed through); `503` retry with the same details.

### `GET /api/booking-services`
- **Who:** signed-in. Booking must be visible to the caller (database).
- **Input (query):** `booking` uuid, required.
- **Success:** `200` booked services for the booking (shape unclear from code).
- **Errors:** `400`; `401`; `404` "Could not find a booking you can access."; `503`.

### `POST /api/booking-services`
- **Who:** signed-in; booking must belong to or be accessible by the caller (database). Same-origin required.
- **Input (JSON):** `bookingId` uuid; `requestId` uuid; `revision` integer 0-2147483647; `services` array of 1-20 strings (each 1-64); `coating` optional object (under 3000 chars); `priceFingerprint` optional (only used when `coating` is sent; its type is not validated in the route).
- **Success:** `200` saved services data (shape unclear from code).
- **Errors:** `400`; `401`; `404` no booking you can access (also used for permission failures); `409` stale revision (message passed through); `503`.

### `GET /api/bookings/requests`
- **Who:** signed-in (the database returns the caller's own change requests).
- **Input (query):** `booking` uuid, repeated for each booking; 1-20 unique values.
- **Success:** `200` change requests for those bookings (shape unclear from code).
- **Errors:** `400` none/too many/invalid ids; `401`; `503`.

### `POST /api/bookings/requests`
- **Who:** signed-in customer who owns the booking (database). Same-origin required.
- **Input (JSON):** `bookingId` uuid; `submissionId` uuid (retry key); `kind` `"cancel"` or `"reschedule"`; `reason` string up to 500. For `reschedule`: `date` and `hour` (integer 9-16) are required. For `cancel`: `date` and `hour` must be absent or null.
- **Success:** `200` `{ id: uuid }` (the change request).
- **Errors:** `400` invalid input or database rejected the visit; `401`; `404` booking not found; `409` already a pending request, or rejected by database (message passed through); `503`.

### `PATCH /api/bookings/requests`
- **Who:** signed-in customer who owns the request (database). Same-origin required.
- **Input (JSON):** `requestId` uuid (the change request id).
- **Success:** `204` request withdrawn.
- **Errors:** `400`; `401`; `404` request not found; `409` "The shop already reviewed this request."; `503`.

### `GET /api/bookings/activity`
- **Who:** signed-in. Rows are filtered by database access rules (route does not check ownership itself).
- **Input (query):** `booking` uuid, required.
- **Success:** `200` `{ events: [{ id, kind, to_status, created_at }] }`, up to the 50 latest, returned oldest first.
- **Errors:** `400`; `401`; `503`.

### `GET /api/bookings/shared`
- **Who:** verified customer who owns the booking (database; route has no sign-in check).
- **Input (query):** `booking` uuid, required.
- **Success:** `200` `{ note: string, photoCount: number, sharedAt: string | null }`: what staff chose to share with the customer.
- **Errors:** `400`; `404` booking not found (also used for permission failures); `503`.

### `GET /api/bookings/shared-photo`
- **Who:** the customer who owns the booking (access checked through the same database function as `/shared`). The file is then fetched with a server-side storage key.
- **Input (query):** `booking` uuid; `photo` index `0`, `1` or `2`.
- **Success:** `200` image bytes (`image/jpeg`, `image/png` or `image/webp`), `Cache-Control: private, no-store`.
- **Errors:** `400`; `404` not shared or not found; `503` storage unavailable.

---

## Staff

All staff endpoints rely on database grants. Endpoints marked "confirmed email" also check the Supabase user has a confirmed email in the route.

### `GET /api/staff/workspace`
- **Who:** signed-in staff with a confirmed email.
- **Input:** none.
- **Success:** `200` the caller's workspace permissions (see `WorkspaceAccess` in Shared types).
- **Errors:** `401`; `403` unconfirmed email or no staff access; `503`.

### `GET /api/staff/counts`
- **Who:** staff (Booking access); no sign-in check in route.
- **Input:** none.
- **Success:** `200` pending booking and change-request totals (shape unclear from code).
- **Errors:** `403`; `503`.

### `GET /api/staff/calendar`
- **Who:** staff (booking calendar access); no sign-in check in route.
- **Input (query):** `from` date, `through` date, both required (up to 63 dates).
- **Success:** `200` calendar data (shape unclear from code).
- **Errors:** `400` bad or too-long range; `403`; `503`.

### `GET /api/staff/bookings`
- **Who:** staff with a confirmed email (database grants).
- **Input (query):** either `view=requests` with `page` integer 1-251 (default 1); or `date` (required) for a day schedule.
- **Success:** `200` `{ requests: [...], hasMore: boolean }` for `view=requests` (20 per page); otherwise the day's bookings with options (shape unclear from code).
- **Errors:** `400`; `401`; `403`; `404`; `503`.

### `POST /api/staff/bookings`
- **Who:** staff with a confirmed email; the needed grant depends on `action` (database-enforced). Same-origin required.
- **Input (JSON):** by `action`:
  - `share`: `bookingId` uuid, `note` string up to 1000, `photos` boolean.
  - `change`: `bookingId` uuid, `requestId` uuid, `kind` `"cancel"`/`"reschedule"`, `originalDate` date, `originalHour` integer 9-16 or `null`, `reason` string up to 500; for `reschedule` also `date` and `hour` (9-16), and `originalHour` must not be null; for `cancel`, `date`/`hour` must be absent.
  - `review`: `requestId` uuid, `decision` `"approved"`/`"declined"`.
  - `confirm`: `bookingId` uuid, `note` string up to 500.
  - `open_date`, `close_date`, `restore_date`: `date` required, no `hour`.
  - `block_slot`, `unblock_slot`: `date` and `hour` (9-16) required.
- **Success:** `204`.
- **Errors:** `400` invalid input or unknown action; `401`; `403`; `404`; `409` booking no longer pending / slot taken / request already reviewed; `503`.

### `POST /api/staff/manual-booking`
- **Who:** staff with a confirmed email and permission to create customer bookings (database). Same-origin required.
- **Input (JSON):** always `email` (complete address, up to 254) and `action`.
  - `lookup`: finds the verified customer. Returns `200` the customer record (shape unclear from code).
  - `book`: `customerId` uuid, `requestId` uuid, `date`, `hour` (integer 9-16, or `null` when `walkIn` is true), `walkIn` optional boolean, `services` 1-20 strings (each up to 64), `bike` up to 120, `name` up to 120, `phone` up to 40, `plate` up to 30 (all required strings), `coating` optional object (under 3000 chars), `priceFingerprint` optional (not type-checked in route).
- **Success:** `200` customer record (lookup) or created booking data (book) (shape unclear from code).
- **Errors:** `400`; `401`; `403` unconfirmed email or no permission; `404` no unique verified account matched / account no longer matches; `409` slot unavailable or `{ code: "price_changed", message }`; `503`.

### `POST /api/staff/records`
- **Who:** staff with booking-records access (database; route has no sign-in check). Same-origin required.
- **Input (JSON, all required):** `from` and `through` (both dates, or both empty strings for no date filter); `search` string up to 254; `status` one of `all`, `pending`, `confirmed`, `done`, `cancelled`; `source` one of `all`, `online`, `walk-in`; `page` integer 1-500; `report` boolean.
- **Success:** `200` booking records page (shape unclear from code).
- **Errors:** `400` invalid filters or range over 366 days; `403`; `503`.

### `POST /api/staff/customers`
- **Who:** staff with customer access (database; route has no sign-in check). Uses POST so emails and ids stay out of URLs. Same-origin required.
- **Input (JSON):** `operation` `"directory"` or `"visits"`.
  - `directory`: `term` string, trimmed, either empty or 2-254 chars; `cursor` optional uuid (last customer id from the previous page).
  - `visits`: `customer` uuid; `page` integer 1-50.
- **Success:** `200` directory page or customer details with visits (shape unclear from code).
- **Errors:** `400`; `403`; `404` customer not found; `503`.

### `GET /api/staff/activity`
- **Who:** Owner permission (database).
- **Input (query):** `from` date, `through` date, both required (up to 31 days).
- **Success:** `200` activity log labels (shape unclear from code).
- **Errors:** `400`; `403`; `503`.

### `GET /api/staff/mfa`
- **Who:** any signed-in user (no staff check in the route). Lists the caller's own verified authenticator factors.
- **Input:** none.
- **Success:** `200` `[{ id: string, name: string | null }]`.
- **Errors:** `401`; `503`.

### `POST /api/staff/mfa`
- **Who:** any signed-in user with a verified authenticator factor. Same-origin required.
- **Input (JSON):** `factorId` string (must be one of the caller's verified factors); `code` 6-digit string.
- **Success:** `204`, session raised to assurance level 2.
- **Errors:** `400` unknown factor, bad format or wrong code; `401`; `429`; `503`.

### `GET /api/staff-access`
- **Who:** verified Owner or Superadmin with the matching grants (database).
- **Input:** none.
- **Success:** `200` staff access list for the UI (shape unclear from code).
- **Errors:** `401`; `403`; `404`; `409`; `400`; `503` (all mapped from the database error).

### `POST /api/staff-access`
- **Who:** verified Owner or Superadmin with matching grants (database). Same-origin required.
- **Input (JSON):** `name` string 1-120; `role` `"staff"`, `"admin"` or `"restricted_admin"`; `enabled` boolean; `pages` array of up to 20 strings (each 1-60); `actions` array of up to 40 strings (each 1-60). To create: `email` valid address up to 254. To edit: `targetId` uuid and `revision` integer 1-2147483647 (editing is chosen when `targetId` is a string).
- **Success:** `204`.
- **Errors:** `400`; `401`; `403`; `404` "Ask this person to create and verify a HERCO account first."; `409` account changed, reload; `503`.

---

## Pricing

### `GET /api/pricing`
- **Who:** staff with pricing permission (database; no sign-in check in route).
- **Input:** none.
- **Success:** `200` service and promotion pricing (shape unclear from code).
- **Errors:** `403`; `503`.

### `POST /api/pricing`
- **Who:** staff with the relevant pricing permission. Same-origin required.
- **Input (JSON):** common: `requestId` uuid, `revision` integer 0-2147483647, `code` string matching `^[a-z0-9][a-z0-9-]{0,63}$`, `label` string 1-120, `enabled` boolean, `operation` `"service"` or `"promotion"`.
  - `service`: `priceCentavos` integer >= 0; `quoteRequired` boolean (default false); `maxCentavos` optional integer greater than the price; `days` array of 1-7 integers 0-6. Rules: when enabled and not quote-only, price must be above 0; when quote-only, price must be 0 and no max.
  - `promotion`: `discountBps` integer 0-10000 (basis points; must be above 0 when enabled); `revision` must not be 0.
- **Success:** `200` saved record (shape unclear from code).
- **Errors:** `400`; `403`; `409` pricing changed (reload); `503` retry the same change.

### `GET /api/pricing/coating-rules`
- **Who:** staff with pricing permission (database).
- **Input:** none.
- **Success:** `200` coating rules (shape unclear from code).
- **Errors:** `403`; `503`.

### `POST /api/pricing/coating-rules`
- **Who:** staff with pricing permission. Same-origin required.
- **Input (JSON):** `requestId` uuid; `id` uuid or `null` (null means create, and then `revision` must be 0; otherwise it must not be 0); `revision` integer 0-2147483647; `service` `"ceramic"` or `"wheel-colour"`; `bike` string up to 120; `options` object; `minimumCentavos` integer >= 0; `maximumCentavos` integer greater than minimum, or `null`; `quoteRequired` boolean (then min must be 0 and max null); `enabled` boolean.
- **Success:** `200` saved rule (shape unclear from code).
- **Errors:** `400` (database message passed through); `403`; `409` stale revision or rule already exists for that bike and configuration; `503`.

### `GET /api/pricing/catalog`
- **Who:** staff with pricing permission (database).
- **Input:** none.
- **Success:** `200` UI pricing configuration (shape unclear from code).
- **Errors:** `403`; `503`.

### `POST /api/pricing/catalog`
- **Who:** staff with pricing permission. Same-origin required.
- **Input (JSON):** `requestId` uuid; `revision` safe integer >= 1; `config` object (not array, under 20,000 chars JSON).
- **Success:** `200` saved configuration (shape unclear from code).
- **Errors:** `400` "Check every rate and range."; `403`; `409` prices changed; `503`.

---

## Points

### `GET /api/points`
- **Who:** signed-in. Returns the caller's own points.
- **Input:** none.
- **Success:** `200` points balance and history (shape unclear from code).
- **Errors:** `401`; `503`.

### `POST /api/points`
- **Who:** verified customer. Same-origin required.
- **Input (JSON):** `rewardId` uuid; `requestId` uuid (retry key).
- **Success:** `200` `{ id }` (redemption id).
- **Errors:** `400` invalid input or redemption no longer available; `401`; `403` verify your email; `409` not enough points; `503`.

### `GET /api/points/rewards`
- **Who:** public (no sign-in check in the route; database decides).
- **Input:** none.
- **Success:** `200` reward preview (shape unclear from code).
- **Errors:** `503`.

### `GET /api/staff-points`
- **Who:** staff with points permission (database; no sign-in check in route).
- **Input (query):** `search` string up to 254 (default empty); `member` optional uuid.
- **Success:** `200` points workspace data (shape unclear from code).
- **Errors:** `400`; `403`; `503`.

### `POST /api/staff-points`
- **Who:** staff with points permission. Same-origin required.
- **Input (JSON):** by `action`:
  - `adjust`: `member` uuid, `requestId` uuid, `delta` safe integer (positive or negative; no range limit in route), `reason` string up to 300.
  - `approve` or `claim`: `receipt` uuid (reviews a points receipt).
  - `saveReward`: `id` uuid, `label` string up to 120, `scope` string up to 200, `cost` safe integer (no minimum in route), `enabled` boolean.
- **Success:** `200` `{ saved: true }`.
- **Errors:** `400` invalid input or unknown member/reward; `403`; `409` balance or approval status check failed; `503`.

---

## Inventory

### `GET /api/inventory`
- **Who:** staff with inventory permission (database; no sign-in check in route).
- **Input (query):** `from` date (default first day of the current month), `through` date (default today, UTC), `item` optional uuid (history filter).
- **Success:** `200` inventory workspace data (shape unclear from code).
- **Errors:** `400`; `403`; `503`.

### `POST /api/inventory`
- **Who:** staff with inventory permission. Same-origin required.
- **Input (JSON):** by `operation`:
  - `option`: `requestId` uuid, `kind` `"unit"` or `"category"`, `name` string up to 60, `previous` string or `null` (null adds; a name renames).
  - `create`, `edit`, `move`: `requestId` uuid, `stockId` uuid, `details` object (under 3000 chars JSON).
- **Success:** `200` `{ saved: true }` for `option`; otherwise the saved item data (shape unclear from code).
- **Errors:** `400`; `403`; `409` item changed, name already exists, or stock out of range; `503`.

### `GET /api/inventory/export`
- **Who:** staff with inventory permission (database; no sign-in check in route).
- **Input (query):** `kind` `"stock"` or `"movements"`; for `movements` also `from` and `through` dates (required).
- **Success:** `200` CSV file (`text/csv; charset=utf-8`, UTF-8 BOM, `Content-Disposition: attachment; filename="herco-inventory-<kind>.csv"`). Cells beginning with `= + - @` are prefixed with `'` (spreadsheet formula protection). Columns for `stock`: name, category, unit, quantity, minimum, supplier, storage_location, unit_cost, billing_rate, capacity. Columns for `movements`: recorded_at_ph, name, unit, operation, before_quantity, after_quantity, reason, actor_id.
- **Errors:** `400`; `403`; `503`.

---

## Reports & analytics

### `GET /api/reports`
- **Who:** staff with report permission (database; no sign-in check in route).
- **Input (query):** `from` date, `to` date, both required (up to 366 days).
- **Success:** `200` booking report (shape unclear from code).
- **Errors:** `400`; `403`; `503`.

### `GET /api/analytics`
- **Who:** public.
- **Input:** none (reads the `herco-analytics` cookie).
- **Success:** `200` `{ enabled: boolean, status: "on" | "off" | "unset" }`. `enabled` is true when the server has Google Analytics credentials configured.
- **Errors:** none.

### `PUT /api/analytics`
- **Who:** public. Same-origin required. Stores the visitor's analytics choice.
- **Input:** plain-text body (not JSON), at most 64 bytes: `allow` or `decline`.
- **Success:** `204`. Sets the HTTP-only `herco-analytics` cookie for 180 days: a random UUID for `allow`, or `off` for `decline`.
- **Errors:** `400` other value, body too long, or `allow` when analytics is not configured.

### `POST /api/analytics`
- **Who:** public. Same-origin required. Silently does nothing (`204`) if analytics is not configured or the visitor has not allowed it.
- **Input:** plain-text body (not JSON), at most 64 bytes, one of `booking_started`, `service_selected`, `booking_submitted`, `change_request_submitted`.
- **Success:** `204`. Forwards the event name to Google Analytics (2 s timeout; delivery failures are ignored, no personal data sent).
- **Errors:** `400` unknown event or body too long.

---

## Walk-in

### `GET /api/walk-in-bookings`
- **Who:** verified customer.
- **Input:** none.
- **Success:** `200` walk-in form data (shape unclear from code).
- **Errors:** `401`; `403` verify your email; `503`.

### `POST /api/walk-in-bookings`
- **Who:** verified customer. Same-origin required.
- **Input (JSON):** `requestId` uuid; `date`; `services` 1-20 strings (each up to 64); `bike` up to 120; `name` up to 120; `phone` up to 40; `plate` up to 30; `formVersion` string 1-60; `signerName` string 1-120; `acknowledged` must be `true`; `coating` optional object (under 3000 chars); `priceFingerprint` optional 32 lowercase-hex string.
- **Success:** `200` created walk-in booking data (shape unclear from code).
- **Errors:** `400` (database message passed through for some cases); `401`; `403`; `409` conflict (message passed through) or `{ code: "price_changed", message }`; `503` retry with the same details.

### `GET /api/walk-in-intake`
- **Who:** signed-in; booking must be visible to the caller (database).
- **Input (query):** `booking` uuid, required.
- **Success:** `200` intake status and form (shape unclear from code).
- **Errors:** `400`; `401`; `403`; `404`; `409`; `503`.

### `POST /api/walk-in-intake`
- **Who:** signed-in; permission depends on `action` (staff request, customer sign; database-enforced). Same-origin required.
- **Input (JSON):** `bookingId` uuid; `formVersion` string 1-60; `action`:
  - `request`: no more fields.
  - `sign`: `name` string 1-120 (trimmed); `acknowledged` must be `true`.
- **Success:** `204`.
- **Errors:** `400`; `401`; `403`; `404`; `409` intake no longer open; `503`.

---

## Completion

### `GET /api/completion`
- **Who:** staff with completion permission (database; no sign-in check in route).
- **Input (query):** `booking` uuid, required; `photo` optional index `0`-`2`.
- **Success:** without `photo`: `200` `{ count: number }`. With `photo`: `200` image bytes (`image/jpeg`, `image/png` or `image/webp`).
- **Errors:** `400`; `403`; `404` photo not found; `503`.

### `PUT /api/completion`
- **Who:** staff with completion permission. Same-origin required. Uploads one photo.
- **Input:** query `booking` uuid; body is the raw image bytes (not JSON), up to 4 MB. Type is detected from the file header (JPEG, PNG or WebP), not from `Content-Type`.
- **Success:** `201` `{ path: string }` (storage path to pass to `POST /api/completion`).
- **Errors:** `400` not an image or empty; `403`; `409` booking does not accept photos; `413` over 4 MB; `503`.

### `POST /api/completion`
- **Who:** staff with completion permission (changing the final price needs price-adjustment permission). Same-origin required.
- **Input (JSON):** `booking` uuid; `priceCentavos` safe integer >= 0; `photos` array of 1-3 strings (storage paths from the upload, each up to 125 chars); `note` string up to 500.
- **Success:** `200` `{ completedAt: string }`.
- **Errors:** `400`; `403` (different message when the price changed without price-adjustment permission); `409` wrong status or unfinalized prices; `413`; `503` retry with the same details.

---

## Health

### `GET /api/health`
- **Who:** public.
- **Input:** none.
- **Success:** `200` `{ status: "configured" }`, `Cache-Control: no-store`.
- **Errors:** `503` `{ status: "configuration-required" }` when the Supabase URL or key is missing.

---

## Shared types

- **`ErrorResponse`:** `{ message: string }`.
- **`ErrorWithCode`:** `{ code: string, message: string }`. Used for `403 email_confirmation_required` (sign-in) and `409 price_changed` (customer booking, staff manual booking, walk-in booking). On `price_changed`, re-estimate and resubmit with the new `priceFingerprint`.
- **`requestId` / `submissionId`:** client-generated UUID reused on retry.
- **`PriceFingerprint`:** 32-character lowercase hex string from the price estimate; sent back on booking calls to detect price changes.
- **`Coating`:** a free-form JSON object (not an array), under 3000 characters when serialised. Its inner fields are defined by the database (unclear from code).
- **`Booking` (from `GET /api/bookings`):** `{ id, reference_no, visit_date, visit_hour, bike, status, original_services, original_total_centavos, current_services, current_total_centavos, coating_options, current_coating_options, created_at, approved_at, completed_at, cancelled_at }`. Statuses seen in code: `pending`, `confirmed`, `done`, `cancelled`. Service entries can include `quote_required` and `max_centavos`.
- **`Availability`:** returned by the `herco_availability` function; shape unclear from code. Calendar hours are 9-16.
- **`WorkspaceAccess`:** permission object from `herco_workspace_permissions`, parsed by `parseWorkspaceAccess` in `src/lib/shared/workspace-navigation.ts` (not read for this document; shape unclear from code).
- **`StaffAccessGrant` (staff-access):** roles `staff`, `admin`, `restricted_admin`; `pages` and `actions` are arrays of grant-name strings (names defined in the database; unclear from code).
