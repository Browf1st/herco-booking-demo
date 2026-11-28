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
- **IDs/dates:** `uuid` means a 36-character hex UUID. `date` means `YYYY-MM-DD`. Money is whole centavos (integers). Hours are integers `0` to `23` where validated; a date's bookable hours run from its opening hour to its closing hour inclusive (a 9-17 shop books `9` to `17`; the closing hour itself is bookable, and a closing hour of 24 ends at `23`).
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

## Maintenance reminders (F-017)

Six months after staff mark a booking Done, the customer gets one email at 9 AM Philippine time (see F-017). Booking emails are not affected by these settings.

### `POST /api/reminders/unsubscribe`
- **Who:** public: a valid signed token is the only credential (no sign-in). Same-origin required (call it from the unsubscribe page, `/reminders/unsubscribe`).
- **Input (JSON):** `token` string, 1-200 chars, required. It is the `token` query value of the link in the email: `/reminders/unsubscribe?token=<token>`. Send it as received (the browser already decodes the query value).
- **Success:** `204` no body. Repeating a valid token, or using it after the customer already unsubscribed, is also `204`. Only maintenance reminders stop, for that customer, for all their jobs.
- **Errors:** `400` token missing, malformed, edited, signed for another purpose, or older than 1 year (`"This link doesn't work any more."`: show the "link invalid or expired" state); `403` same-origin check failed; `413`; `503` backend or reminder settings not configured (show the retry state).
- The app has no rate limiter of its own (see the `429` note above). The signature is checked before any database call.

### `GET /api/account/reminders`
- **Who:** signed-in customer. Reads only the caller's own setting.
- **Success:** `200 { maintenance: boolean }`. `true` (default) means reminders are on.
- **Errors:** `401`; `503`.

### `PUT /api/account/reminders`
- **Who:** signed-in customer, own setting only. Same-origin required.
- **Input (JSON):** `maintenance` boolean, required (a string or number is `400`). `false` stops maintenance reminders, `true` turns them back on (also after an email unsubscribe).
- **Success:** `200 { maintenance: boolean }` (the saved value).
- **Errors:** `400`; `401`; `403` same-origin; `503`.

---

## Availability & catalog

### `GET /api/availability`
- **Who:** public (no sign-in check in the route; the database function decides what is returned).
- **Input (query):** `from` date, `to` date, both required.
- **Success:** `200` array of `Availability` rows (see Shared types): only hours the shop can take, each `status: "open"`, plus `openHour`/`closeHour`/`closed` per date. Hours follow the admin's default hours and open weekdays, and each date's own hours or closed choice. Until the admin saves new hours the result is 9 AM-5 PM slots, Wednesday-Sunday. The closing hour itself is bookable (a 9-17 shop lists hours 9 to 17; before the inclusive-closing change the last slot was 16). A closing hour of 24 still ends at 23:00. No `booked` status and no counts.
- **Errors:** `400` missing or badly formatted dates, or range rejected ("up to 42 days within the booking calendar"); `503`.

### `GET /api/shop-hours`
- **Who:** public, no sign-in needed. Same answer for everyone.
- **Input:** none.
- **Success:** `200 { openHour: number, closeHour: number, openWeekdays: number[] }`: the admin's current default hours (0-23 and 1-24, closing after opening; 9 and 17 until changed; the closing hour itself is bookable, so the last slot starts at `closeHour`) and open weekdays (0 = Sunday ... 6 = Saturday, sorted; Wednesday-Sunday is `[0,3,4,5,6]` until changed). Dates with their own hours or a closed choice are not reflected (use `/api/availability`). No private data. `Cache-Control: public, max-age=60`.
- **Errors:** `503` "Opening hours are temporarily unavailable." (not cached).

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
- **F-021 note:** same client shape as before; powder wheel prices now resolve from `config.powderModel` (colour category x bike size, with exceptions). `custom` colours and `not-sure` size are quote only. The customer catalog hides exception notes and disabled exceptions.

### `POST /api/coating-estimate`
- **Who:** verified customer (route has no explicit sign-in check; database reports `403`). Same-origin required.
- **Input (JSON):** `bike` string, trimmed, 1-120, required; `services` array of 1-20 strings (each 1-64 chars), required; `coating` optional object (JSON length under 3000 chars; not an array).
- **Success:** `200` price preview from the database (shape unclear from code; fields used elsewhere include a price fingerprint, see Shared types `PriceFingerprint`).
- **Errors:** `400` invalid input, or the database rejected the configuration (message passed through); `403` "Verify your email before preparing a booking."; `503`.
- **F-021 note:** same request and response shape; powder wheel lines now resolve via `config.powderModel` (custom or not-sure size = quote required).
- **F-022 note (also applies to `POST /api/bookings` and `POST /api/booking-services`, which use the same `coating` options):** `coating.ui_catalog` now also accepts `powder_category` (`basic`, `special`, `luminous-prismatic`, `custom`, or empty), `color_id` (uuid or empty), `custom_note` (text, trimmed, cut to 300 chars; meant for `custom`) and `from_finish` (optional text up to 100). `wheel_type` also accepts the size keys `10-14`, `17`, `big-bike`, `not-sure`, in addition to the old labels. `raider_sniper_confirmed` is optional and ignored; the 15-17 in size (`17`) no longer needs a Raider or Sniper. Unknown keys are still refused (`400`). The server prices from its own colour list (matching `color_id`, else `finish` by id or name); `powder_category` is stored but never used to set a price. A finish that matches no colour, a `custom` colour, or size `not-sure` returns a quote.
- **F-023 note:** for ceramic, `coating.ui_catalog.ceramic_addons` is an ARRAY of the selected add-on names (multi-select; up to the 7 known add-ons, each once). Staff per-bike ceramic prices come from `config.powderModel.exceptions` entries with `service: "ceramic"` (`bikeKey` lowercase and trimmed, `priceCentavos` or `quoteOnly: true`, `enabled`; `finish` optional and `fromFinish` not allowed for ceramic; one exception per bike). The ceramic line price is: enabled ceramic exception for the bike, else the existing `config.ceramic` tier price, else quote. Add-ons keep pricing from `config.ceramic`. Response shape unchanged.

---

## Bookings (customer)

### `GET /api/bookings`
- **Who:** signed-in. Returns only the caller's own bookings (filtered by their user id).
- **Input (query):** `page` integer 1-500, default 1 (page size 20).
- **Success:** `200` `{ bookings: Booking[], hasMore: boolean }`. Each booking adds `approved_at`, `completed_at`, `cancelled_at` (ISO timestamps or `null`). Newest first. Each booking also carries `original_services` and `original_total_centavos` (fixed at booking time) and `current_services` and `current_total_centavos` (both `null` until the booking is edited; then use them as the shown services and total, with the original total struck through when different). Staff price changes appear here. Each booking also has `shop_priced: boolean` (new): `true` once staff changed any line price. When `true`, hide **Edit services** and show "The shop updated this booking after inspection. Contact the shop to change services."
- **Errors:** `400` bad page; `401`; `503`.

### `POST /api/bookings`
- **Who:** verified customer (route checks signed in; database reports `403` for unverified). Same-origin required.
- **Input (JSON):** `requestId` string (retry key); `date` string; `hour` integer 0-23 (the database refuses an hour that is not open for that date: `409`); `services` array of 1-20 strings (each up to 64); `bike` string; `name` string; `phone` string (may be empty: the mobile number is optional for a customer's own online booking; if not empty, the route requires 7-15 digits with only `+`, spaces, `()` and `-`, same rule as `/api/auth/contact`, else `400 "Enter a valid mobile number, or leave it blank."`; the database also caps it at 40 characters); `plate` optional string; `coating` optional object (under 3000 chars JSON); `priceFingerprint` optional 32 lowercase-hex string. Lengths of `bike`, `name`, `phone`, `plate` and the date/hour ranges are not checked in the route (database decides, unclear from code).
- **Success:** `200` `{ id: uuid, status: string, totalCentavos: number, estimateOpen: boolean }`. `estimateOpen` is true when any service needs a quote or has a price range.
- **Errors:** `400` invalid input; `401`; `403` verify your email; `409` slot unavailable, or `{ code: "price_changed", message }` when prices changed since the estimate; `503` retry using the same `requestId`.

### `GET /api/bookings/history`
- **Who:** signed-in customer who owns the booking (database-enforced). Not for staff: staff use `GET /api/staff/booking-history`.
- **Input (query):** `booking` uuid, required.
- **Success:** `200` `{ booking_id: uuid, entries: Entry[] }`, newest first, at most 200. Header `Cache-Control: private, no-store`. Each entry: `at` (ISO timestamp), `kind` (`price_changed`, `price_corrected`, `service_added`, `service_removed`, `booked`, `approved`, `completed`, `cancelled`, `rescheduled`), `actor` (`"you"` or `"shop"`), and for price and service kinds `service_label` plus `from_centavos` / `to_centavos` (a missing side means no previous or no new price). A booking with no changes returns `entries: []`.
- **Never includes:** staff names, change reasons, private notes, phone numbers or emails. Amounts are the customer's own booking amounts.
- **Errors:** `400` bad booking id; `401` not signed in; `403` the booking is not yours or does not exist (same answer for both); `404` reserved; `503`.

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
- **Success:** `200` booked services for the booking (`original`, `current`, `totalCentavos`, `revision`, `date`, `canEdit`, `changes`, `bike`, `options`, `shop_priced: boolean`, and new `contact: { name, phone, plate }` (strings, empty when not stored; the email is never included)). When `shop_priced` is true, `canEdit` is `false` for the booking's customer (staff keep their own `canEdit`). When the caller is staff without `viewIncome`, `totalCentavos` is `null` and the lines in `original`, `current` and `changes` have no `price_centavos`, `max_centavos` or `promotion`; customers always see their own prices.
- **Errors:** `400`; `401`; `404` "Could not find a booking you can access."; `503`.

### `POST /api/bookings/edit`
- **Who:** signed-in customer who owns the booking (checked in the database). Same-origin required. The booking must be Pending and its visit in the future; once the shop priced the booking the customer can no longer edit it.
- **Input (JSON):** `bookingId` uuid; `requestId` uuid (resend the same one when retrying); `revision` integer 0-2147483647 (from `GET /api/booking-services`); `services` array of 1-20 strings (each 1-64); `coating` optional object (under 3000 chars, same options as `POST /api/bookings`); `bike` string 1-120; `name` string 1-120; `phone` string, empty allowed, otherwise a valid mobile number (same rule as `POST /api/bookings`); `plate` string 0-30; `priceFingerprint` optional 32 lowercase hex characters.
- **Behaviour:** prices are recalculated on the server for the new motorcycle and services. The current services, total, options, motorcycle and contact (name, phone, plate) are replaced and `revision` goes up by one; the original booking snapshot and the email never change. If nothing changed, the revision stays the same.
- **Success:** `200` same shape as `GET /api/booking-services` (includes `contact`).
- **Errors:** `400` invalid input; `401` not signed in; `404` no booking you can access (also for someone else's booking); `409` `{ code, message }` with `code` `"booking_locked"`, `"line_changed"` (stale revision: reload) or `"shop_priced"` (same meaning as `POST /api/booking-services`); `503` retry.

### `POST /api/booking-services`
- **Who:** signed-in; booking must belong to or be accessible by the caller (database). Same-origin required.
- **Input (JSON):** `bookingId` uuid; `requestId` uuid; `revision` integer 0-2147483647; `services` array of 1-20 strings (each 1-64); `coating` optional object (under 3000 chars); `priceFingerprint` optional (only used when `coating` is sent; its type is not validated in the route).
- **Success:** `200` saved services data (shape unclear from code).
- **Errors:** `400`; `401`; `404` no booking you can access (also used for permission failures, so staff without `editServices` see `404` here, not `403`); `409` `{ code, message }` where `code` is `"booking_locked"` ("This booking can no longer be changed.": the booking is no longer open to edits, for staff Pending or Booked from today on) or `"line_changed"` (the revision is stale: reload) or `"shop_priced"` (new: staff changed a price on this booking, so the customer can no longer edit its services; `message` is "The shop updated this booking after inspection. Contact the shop to change services."; the same `code` is returned to staff who send `coating` on a shop-priced booking, with a message to add or remove services one by one so prices are kept); `503`. The `code` field is new; `message` is unchanged in shape.
- **Staff "Add service" / remove:** this is the existing staff path (grant `editServices`, checked in the database). Send the full list of service codes wanted: the current codes from `GET /api/booking-services` (`current[].code`) plus the new one, with the `revision` from that GET. A new service is added at today's catalog price; each add/remove is logged and shows in `GET /api/staff/booking-history` as `service_added` / `service_removed`. To then set a different price for the new line, call `POST /api/staff/line-price`.

### `POST /api/staff/line-price`
- **Who:** staff with grants `adjustPrices` **and `viewIncome`** (database-enforced; page Bookings or Booking history). Without `viewIncome` the server refuses with `403` (the screen already hides Edit price then), so no amounts are ever returned to a caller without it. Signed-in check in the route (`401`). Same-origin required.
- **When:** only while the booking is Pending or Booked. After Done use `POST /api/booking-prices`.
- **F-026 UI note (updated 2026-11-28):** the staff price editor shows **one editable box per part of the line** — the base service plus each chosen option (e.g. Powder Coating ₱1,999 and Matte to Glossy ₱599) — each prefilled with its current price, with a **New total** that auto-sums as you type. A line with no options is a single box (its base). The same breakdown is shown wherever the booking's details appear (staff Reports, staff booking history, the Customers directory popup, and the customer booking history with the staff reason hidden).
- **Input (JSON):** `booking` uuid; `requestId` uuid (retry key: the same staff member re-sending the same request with the same values gets the saved result, even after the booking moved on); `service` string 1-100 (the line's `code`); `expectedCentavos` integer >= 0 or `null`: the line's current total `price_centavos` exactly as read (a quote-only line is stored with 0 or no price: send `0` or `null`, both match); `reason` string, 1-200 after trim; **and one of**:
  - `parts`: an array (1-20) of `{ label: string (1-120), pesos: integer 0..1,000,000 }`, one per part of the line **in the order the line's `details` are shown** (for a line with no `details`, a single part = its base). The line total becomes the sum of the parts; the edited line keeps a `details` breakdown with the new per-part prices (a single-part line stays a flat price). The number of parts must match what the staff member saw, else `409 line_changed`.
  - `pesos`: a single whole-peso line total (0..1,000,000) — the original flat-price path, still supported; the edited line drops `details`.
  - A new value equal to the current one (same total and same parts) is `400` "That is already the price." (a quote-only line may be priced at 0).
- **Success:** `200` `{ revision: integer, status: "pending"|"confirmed", lines: ServiceLine[], totalCentavos: integer }`. `lines` are the booking's current lines (`current_services`), `totalCentavos` the new total (sum of the priced lines). The original snapshot (`original_services`, `original_total_centavos`) never changes. On the changed line `max_centavos`, `quote_required` and `promotion` are removed; with `parts` the line keeps a new `details` breakdown, with `pesos` the `details` are dropped. The full old line is kept in the private change log. The booking's `service_revision` goes up by one, so a stale `revision` on `POST /api/booking-services` is refused with `line_changed`.
- **Errors:** `400` invalid input; `401`; `403` no `adjustPrices` grant; `404` booking not found; `409` `{ code: "booking_locked", message: "This booking can no longer be changed." }` (Done or Cancelled) or `{ code: "line_changed", message }` (the line's price is no longer `expectedCentavos`, or the service is no longer on the booking: reload); `503`.

### `GET /api/staff/booking-history`
- **Who:** verified staff with page Bookings, Booking history or Reports (database-enforced). Signed-in check in the route (`401`). Response is `private, no-store`.
- **Input (query):** `booking` uuid, required.
- **Success:** `200` `{ booking_id, canViewIncome, entries }`. `entries` is newest first, at most 200. Every entry has `at` (ISO timestamp), `kind` and `actor` (the staff member's display name, `"HERCO staff"` if none is set, or `"Customer"` when the actor is not staff). Never contains emails, phone numbers or private notes.
  - `kind: "price_changed"`: a pre-Done price change from `POST /api/staff/line-price`. Adds `service_code`, `service_label`, `reason` and (only with `viewIncome`) `from_centavos` (absent when the line had no exact price) and `to_centavos`.
  - `kind: "price_corrected"`: a price correction from `POST /api/booking-prices` (used after Done). Same fields as `price_changed`.
  - `kind: "service_added"`: adds `service_code`, `service_label` and (only with `viewIncome`) `to_centavos` (the price when added). `kind: "service_removed"`: same, with `from_centavos`.
  - `kind: "booked" | "approved" | "completed" | "cancelled" | "rescheduled"`: booking status events; no extra fields.
  - Without `viewIncome` every `*_centavos` field is left out.
- **Errors:** `400` bad id; `401`; `403`; `404` booking not found; `503`.

### `GET /api/bookings/requests`
- **Who:** signed-in (the database returns the caller's own change requests).
- **Input (query):** `booking` uuid, repeated for each booking; 1-20 unique values.
- **Success:** `200` change requests for those bookings (shape unclear from code).
- **Errors:** `400` none/too many/invalid ids; `401`; `503`.

### `POST /api/bookings/requests`
- **Who:** signed-in customer who owns the booking (database). Same-origin required.
- **Input (JSON):** `bookingId` uuid; `submissionId` uuid (retry key); `kind` `"cancel"` or `"reschedule"`; `reason` string up to 500. For `reschedule`: `date` and `hour` (integer 0-23, and open for that date) are required. For `cancel`: `date` and `hour` must be absent or null.
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
  - `change`: `bookingId` uuid, `requestId` uuid, `kind` `"cancel"`/`"reschedule"`, `originalDate` date, `originalHour` integer 0-23 or `null`, `reason` string up to 500; for `reschedule` also `date` and `hour` (0-23, must be open for that date), and `originalHour` must not be null; for `cancel`, `date`/`hour` must be absent.
  - `review`: `requestId` uuid, `decision` `"approved"`/`"declined"`.
  - `confirm`: `bookingId` uuid, `note` string up to 500.
  - `open_date` (open with the default hours), `close_date` (closed): `date` required, no `hour`. Both also clear the date's own hours.
  - `restore_date`: `date` required, no `hour`. Removes the date's closed/open choice and own hours; manual blocks stay.
  - `block_slot`, `unblock_slot`: `date` and `hour` (0-23) required. Hours already past (Philippine time) are refused with `400`.
  - `set_date_hours`: `date`, `openHour` (0-23), `closeHour` (1-24, greater than `openHour`), optional `confirmOutside` boolean (default `false`), optional `confirmedOutsideCount` integer 0 or more (the `outsideCount` the staff member was shown; only used with `confirmOutside: true`). Own hours for that date only; the last slot starts at `closeHour` (inclusive).
  - All date actions refuse past dates (Philippine time) with `400`, and need the `manageSchedule` grant (`403` otherwise).
- **Success:** `204`, except `set_date_hours`: `200 { outsideCount: number }`.
- **`409` for `set_date_hours`:** `{ code: "bookings_outside_hours", bookings: [{ reference, date, hour }], outsideCount }` when future bookings (not cancelled, hour still ahead) on that date would fall outside the new own hours and `confirmOutside` is not `true`. The same `409` is returned when `confirmOutside` is `true` and `confirmedOutsideCount` is sent but the recomputed count is higher (more bookings appeared since the warning): the body carries the new list and count so the screen can warn again. `bookings` lists at most 100, no names. Nothing is saved. Send the same request with `confirmOutside: true` (and the `outsideCount` just shown as `confirmedOutsideCount`) to save anyway. Bookings are never moved or cancelled.
- **`400` for `set_date_hours` on a past date:** message `That date has passed.`
- **Errors:** `400` invalid input or unknown action; `401`; `403`; `404`; `409` booking no longer pending / request already reviewed / the time is no longer available (message from the database) / `bookings_outside_hours`; `503`. (`400` for `set_date_hours` also has the message `That date has passed.` for past dates.)
- Changing hours, weekdays, own hours or blocks never changes existing bookings. Every change is written to the schedule log (shown in the Activity log as area "Availability", actions `open_date`, `close_date`, `restore_date`, `block_slot`, `unblock_slot`, `set_date_hours`, `set_default_hours`).

### `GET /api/staff/schedule-settings`
- **Who:** signed-in staff with a confirmed email and the Bookings page (the database checks it; the `manageSchedule` grant is not needed to read).
- **Success:** `200 { openHour: 0-23, closeHour: 1-24, openWeekdays: number[] (0 = Sunday ... 6 = Saturday, sorted), canManage: boolean, version: string }`. `version` is the time the default hours were last saved (ISO string, opaque: send it back unchanged in the next `PUT`). Starting values: `9`, `17`, `[0,3,4,5,6]`. The last slot starts AT `closeHour` (inclusive; a 9-17 shop books 9:00 to 17:00). Before the inclusive-closing change it started at `closeHour - 1`. `closeHour` 24 ends at 23:00.
- **Errors:** `401`; `403`; `503`.

### `PUT /api/staff/schedule-settings`
- **Who:** staff with the `manageSchedule` grant (database-enforced). Same-origin required.
- **Input (JSON):** `openHour` integer 0-23; `closeHour` integer 1-24, greater than `openHour`; `openWeekdays` 1-7 unique integers 0-6; optional `confirmOutside` boolean (default `false`); optional `version` string (from `GET`; when sent and no longer current, nothing is saved and `409 schedule_changed` is returned); optional `confirmedOutsideCount` integer 0 or more (the `outsideCount` the staff member was shown; only used with `confirmOutside: true`). A wrong type is `400`.
- **Success:** `200 { openHour, closeHour, openWeekdays, outsideCount, version }` (`version` is the new current version). `outsideCount` is how many future bookings are now outside the hours (0 unless `confirmOutside` was sent).
- **`409`:** `{ code: "bookings_outside_hours", bookings: [{ reference, date, hour }], outsideCount }` when future bookings (not cancelled, hour still ahead) that were inside the current hours would fall outside the new hours or on a newly closed weekday and `confirmOutside` is not `true`. `bookings` lists at most 100, sorted by date and hour, with no names. Nothing is saved. Bookings already outside the hours (for example on a date closed by hand) are not listed. The same `409` (new list and count, nothing saved) is returned when `confirmOutside` is `true` and `confirmedOutsideCount` is sent but the recomputed count is higher.
- **`409 schedule_changed`:** `{ code: "schedule_changed", message: "Opening hours were changed by someone else. Reload to see the latest." }` when `version` was sent and the hours were saved by someone else since. Nothing is saved. Reload with `GET`.
- **Errors:** `400` with a message (`Choose an opening and closing hour.`, `Closing time must be after opening time.`, `Pick at least one open day.`); `401`; `403` (`You don't have permission to change the schedule.`); `409` as above; `503`.

### `POST /api/staff/manual-booking`
- **Who:** staff with a confirmed email and permission to create customer bookings (database). Same-origin required.
- **Input (JSON):** `action`. Send `email` (complete address, up to 254) for `lookup` and `book`.
  - `lookup`: finds the verified customer. Returns `200` the customer record (shape unclear from code).
  - `book`: `customerId` uuid, `requestId` uuid, `date`, `hour` (integer 0-23 that is open for that date, or `null` when `walkIn` is true; the database refuses other hours with `409`), `walkIn` optional boolean, `services` 1-20 strings (each up to 64), `bike` up to 120, `name` up to 120, `phone` up to 40, `plate` up to 30 (all required strings), `coating` optional object (under 3000 chars), `priceFingerprint` optional (not type-checked in route).
  - `book_guest`: same scheduled-visit fields as `book` except omit `customerId`, `email`, and `walkIn`. Send a nonblank `name`. `phone` is optional and limited to 40 characters. **Added:** optional `email` (empty or absent is fine; if given it must be a complete address up to 254, stored trimmed in the booking contact as `email`, empty string when none) and optional `walkIn: true` with `hour: null`; `date` may be omitted (the server uses today in Philippine time) and, if sent, must be today, which books a same-day walk-in directly as `confirmed` with no hour and no digital intake (a guest has no account to sign it; `intakeRequired` stays false). A non-boolean `walkIn` or an invalid `email` is `400`.
- **Success:** `200` verified customer record for `lookup`, or `{id, reference, status, totalCentavos, intakeRequired, estimateOpen}` for either booking action.
- **Errors:** `400`; `401`; `403` unconfirmed email or no permission; `404` no unique verified account matched / account no longer matches; `409` slot unavailable or `{ code: "price_changed", message }`; `503`.

### `GET /api/staff/booking-detail`
- **Who:** verified staff with any of `Customers`, `Bookings`, `Booking history` or `Reports` (database-enforced). Signed-in check in the route (`401`). Response is `private, no-store`.
- **Input (query):** `booking` uuid, required.
- **Success:** `200` — one booking's full staff record (same shape as a `POST /api/staff/records` row), plus `canViewIncome`. Money fields are null and service amounts stripped without the `viewIncome` grant. Used by the Customers directory to open the shared "More details" popup per booking.
- **Errors:** `400` invalid uuid; `401`; `403`; `404` booking not found; `503`.

### `POST /api/staff/booking-name-groups` — removed
- **Owner decision 2026-11-28:** the "browse bookings by recorded name" feature is retired. The endpoint and its `BookingNameGroup` component were removed because different people can share a recorded name. A customer's previous bookings are reached only through the per-customer, already-scoped `POST /api/staff/customers` `visits` operation. The underlying `herco_staff_booking_name_groups` RPC is left in place but is no longer called by any screen.

### `POST /api/staff/records`
- **Who:** staff with booking-records access (database; route has no sign-in check). Same-origin required. **`report: true` (Reports) is owner/superadmin only** — a non-owner is `403` even with the `Reports` page grant; `report: false` (Booking history) stays open to staff with `Bookings` or `Booking history`.
- **Input (JSON, all required):** `from` and `through` (both dates, or both empty strings for no date filter); `search` string up to 254; `status` one of `all`, `pending`, `confirmed`, `done`, `cancelled`; `source` one of `all`, `online`, `walk-in`; `page` integer 1-500; `report` boolean. Optional `sort`: `"date"` (default, newest visit first), `"date_asc"` (oldest visit first), `"price"` (high to low) or `"price_asc"` (low to high); for both price sorts a done booking uses its final price and the others use their current total (original estimate until staff change a price), and bookings with no price are last; or `"status"` (pending, booked, done, cancelled). `date_asc` and `price_asc` are new. Sorting covers all matching records, not just the page; ties break by newest created, then id, so pages never repeat or skip a row. Any other `sort` value is `400`.
- **Success:** `200` `{ records, metrics, total, page, pages, canViewIncome, sort }`.
  - `sort`: the sort actually applied. Without the `viewIncome` grant `"price"` and `"price_asc"` are applied as `"date"` (the order must not reveal amounts).
  - `search` matches booking id, reference (`HG-n`), bike, customer name, phone, email, plate and the original service labels. Amounts are not searchable without `viewIncome`.
  - `metrics`: `{ total, pending, booked, completed, cancelled, walkIns }`; with `report: true` also `completedValueCentavos` (null without `viewIncome`) and `completedWithoutValue`.
  - `records`: up to 20 rows: `id`, `reference` (`HG-n`), `visit_date`, `visit_hour`, `bike`, `customer_id`, `customer_name`, `customer_phone`, `customer_email`, `plate`, `status` (`pending|confirmed|done|cancelled`), `created_at`, `source` (`online|walk-in`), `services` (labels), `original_services` and `current_services` (arrays of `{ code, label, price_centavos, max_centavos?, quote_required?, promotion?, details? }`), `coating_options`, `approved_at`, `completed_at`, `private_completion_note`, `approval_note`, `shared_note`, `shared_photos`, `photo_count`, `request_pending`, plus the money fields below.
  - Money fields: `final_price_centavos` (done bookings, after any price correction; null if not completed), `original_total_centavos` (the booking-time estimate; stays fixed), `total_centavos` (current total: the sum of the current lines, changes when staff edit prices or services; use it for the Price column of Pending/Booked rows; Done rows use `final_price_centavos`).
  - Search (`search`) matches booking id, reference, bike, customer name, phone (also ignoring spaces and dashes), email, plate and the service labels (current and original), never prices or field names.
  - **Without `viewIncome`:** `final_price_centavos`, `original_total_centavos` and `total_centavos` are `null`, and service lines in `original_services`/`current_services` (and their `details`) have `price_centavos`, `max_centavos` and `promotion` removed (labels and codes remain). `original_total_centavos` is new; all other fields are unchanged apart from the money hiding above.
- **Errors:** `400` invalid filters, sort or range over 366 days; `403`; `503`.

### `POST /api/staff/customers`
- **Who:** staff with customer access (database; route has no sign-in check). Uses POST so emails and ids stay out of URLs. Same-origin required.
- **Input (JSON):** `operation` `"directory"` or `"visits"`.
  - `directory`: `term` string, trimmed, either empty or 2-254 chars; `cursor` optional uuid (last customer id from the previous page).
  - `visits`: `customer` uuid; `page` integer 1-50.
- **Success:** `200` directory page or customer details with visits (shape unclear from code). Directory: `{ customers, nextCursor, total }`, 20 per page ordered by id. `total` and `customers` cover all confirmed customer accounts, staff accounts excluded; a customer with no bookings is included with `name`, `phone` and `bike` null and `booking_count` 0 (before, only customers with a booking were listed and counted).
- **Errors:** `400`; `403`; `404` customer not found; `503`.

### `GET /api/staff/activity`
- **Who:** Owner permission (owner/superadmin with the `Activity log` grant and a verified MFA session; database-enforced).
- **Input (query):** `from` date, `through` date, both required (up to 31 days).
- **Success:** `200` — array (newest first, up to 100) of `{ recorded_at, area, action, actor, actor_label, reference }`.
  - **Bookings rows (2026-11-28):** `action` now states what changed instead of a raw event kind — a line-price edit reads `"<service> price ₱1,999 → ₱2,999"`, a completed-price correction `"Completed price corrected ₱x → ₱y"`, an added service `"Added <service> (₱n)"`, a removed service `"Removed <service>"`, and status changes `"Booked" | "Approved" | "Completed" | "Cancelled" | "Rescheduled"`. `reference` is the booking's `HG-n` (was the raw uuid). Peso figures appear only for an owner who also holds `viewIncome`; otherwise a price edit reads `"<service> price changed"`.
  - Other areas (Availability, Inventory, Pricing, Staff access, HERCO Points) are unchanged.
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
- Retired in F-021: returns 410; the old per-bike rules now live in config.powderModel.exceptions (see /api/pricing/catalog). Both GET and POST return `410 { message: "Coating rules moved into the pricing catalog." }` (POST still requires same-origin). The original description below is kept for history.
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
- **Success:** `200` UI pricing configuration: `{ config, revision, canEdit }`. `config` keeps its existing `ceramic` and `powder` keys and adds `config.powderModel` (F-021, see below).
- **Errors:** `403`; `503`.

`config.powderModel` (powder wheel colour x bike size pricing; pesos are plain numbers, `null` means quote only):
- `categories`: always `["basic","special","luminous-prismatic","custom"]`.
- `baseTable`: `{ <category>: { "10-14", "17", "big-bike", "not-sure" } }` with a price or `null` per size. The `custom` row and every `not-sure` cell are always `null` (quote only).
- `colorEntries[]`: `{ id (uuid), name (1-80), category, photoPath (null or "entry/<this entry's own id>.webp|jpg|png"), quoteOnly (boolean), pricesBySize? }`. `pricesBySize` is an optional per-size override; missing sizes use `baseTable[category][size]`. Category `custom` is always quote only.
- `exceptions[]`: `{ id (uuid), service ("wheel-colour"), bikeKey (lowercase, up to 120), finish, fromFinish (null or text), priceCentavos (integer) or quoteOnly: true, enabled (boolean), note (up to 200) }`. Exceptions win over the base price. Duplicates (same service, bike, finish, fromFinish) are refused.
- `bikeTiers`: `{ <bikeKey>: <size key> }` mapping a bike to its size.

### `POST /api/pricing/catalog`
- **Who:** staff with pricing permission (and MFA, enforced by the database). Same-origin required.
- **Input (JSON):** `requestId` uuid; `revision` safe integer >= 1; `config` object (not array, under 40,000 chars JSON; this is the limit for the whole config including `powderModel`).
- **Success:** `200` saved configuration (shape unclear from code).
- **Errors:** `400` "Check every rate and range." (database `22023` "Check the coating rates." for an invalid `powderModel`); `403` (database `42501`, no pricing permission or MFA); `409` prices changed (database `40001`, stale `revision`; reload and retry); `503`.
- Existing saved bookings keep their original price snapshots; new prices apply to new or edited work only.

### `PUT /api/pricing/color-photo?entry=<uuid>`
- **Who:** staff with pricing permission (checked by the database function `herco_pricing_swatch_target`). Same-origin required.
- **Input:** query `entry` = the colour entry id (uuid, already saved in `config.powderModel.colorEntries`). Body = the raw image bytes (not JSON), up to 4 MB, JPEG, PNG or WebP (checked by file contents, not by name).
- **Success:** `201 { path: "entry/<uuid>.<webp|jpg|png>" }`. Re-uploading replaces the photo. The caller then stores `path` in that entry's `photoPath` and saves via `POST /api/pricing/catalog`.
- **Errors:** `400` invalid `entry`, not an image, or "Save the colour before adding a photo."; `403` no pricing permission; `413` over 4 MB; `503` storage or database unavailable.
- **Storage:** public bucket `herco-swatches` (separate from the private `herco-completion` bucket, which this endpoint never touches).

### `GET /api/pricing/color-photo?entry=<uuid>`
- **Who:** public (colour swatches are marketing images). No sign-in needed.
- **Input:** query `entry` uuid.
- **Success:** `200` the image with its `content-type`, `x-content-type-options: nosniff`, `cache-control: public, max-age=300`.
- **Errors:** `400` invalid `entry`; `404` no photo for this colour; `503`.
- Only the `entry/` folder of `herco-swatches` is read.

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
- **`Booking` (from `GET /api/bookings`):** `{ id, reference_no, visit_date, visit_hour, bike, status, original_services, original_total_centavos, current_services, current_total_centavos, coating_options, current_coating_options, created_at, approved_at, completed_at, cancelled_at, shop_priced }`. Statuses seen in code: `pending`, `confirmed`, `done`, `cancelled`. Service entries can include `quote_required` and `max_centavos`.
- **`Availability`:** array from `GET /api/availability`, one row per open hour: `{ visit_date: "YYYY-MM-DD", visit_hour: 0-23, status: "open", openHour, closeHour, closed: false }`. `openHour`/`closeHour` are that date's first slot hour and closing hour (the last slot starts AT `closeHour`: a 9-17 shop lists hours 9 to 17; `closeHour` is the stored closing hour, 24 ends at 23). Only bookable hours are listed (past, blocked and out-of-hours hours are not). A date with no bookable hour returns one row `{ visit_date, visit_hour: null, status: "closed", openHour, closeHour, closed }`: `closed: true` (and `openHour`/`closeHour` null) when the shop is closed that date, `closed: false` when the date has hours but none left (all past or blocked). `booked` is never returned; any number of customers may share an hour.
- **Staff day view (`GET /api/staff/bookings?date=`) additions:** `slots` now holds only the date's real hours: `[{ hour, status: "open"|"past"|"blocked", blocked: boolean, booked: number }]` (`booked` counts non-cancelled bookings in that hour). New keys: `closed` boolean, `open_hour`, `close_hour` (null when closed; the date's closing hour, and `slots` now include the closing hour itself, e.g. 9 to 17), `own_open_hour`, `own_close_hour` (the date's own hours, else null). `override` is unchanged (`true`/`false`/`null`). Each booking has `outside_hours: boolean`.
- **Staff calendar (`GET /api/staff/calendar`) additions per date:** `closed` (follows the date's real hours), `open_hour`, `close_hour` (the closing hour, itself bookable), `outside_hours` (count of non-cancelled bookings outside the hours; a booking at the closing hour is inside), `hours: [{ hour, booked }]` (non-cancelled bookings per hour). Existing keys `pending`, `booked` (confirmed only), `completed` are unchanged.
- **`WorkspaceAccess`:** permission object from `herco_workspace_permissions`, parsed by `parseWorkspaceAccess` in `src/lib/shared/workspace-navigation.ts` (not read for this document; shape unclear from code).
- **`StaffAccessGrant` (staff-access):** roles `staff`, `admin`, `restricted_admin` (the screens no longer offer `restricted_admin` since 2026-11-23 but still accept and display it as Admin); `pages` and `actions` are arrays of grant-name strings (names defined in the database; unclear from code).
