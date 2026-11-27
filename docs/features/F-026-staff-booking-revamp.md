# F-026: Staff booking screen revamp — slot lists, service type, detail actions, two-box price edit

**Status:** Ready (owner approved 2026-11-26) · **Milestone:** M2 · **Depends on:** F-007, F-024 (shared card + detail pattern), F-025 existing design standards (final polish follows this feature); alongside/after F-024

## In one sentence
Rework the staff Bookings screen so the "All slots" control is tidy, every time slot lists all its bookings with the service type (Ceramic vs Powder) clearly labelled, tapping an entry opens the shared ReportDetails popup with Edit price / Edit service at the top right, the price edit shows two boxes (current + proposed), and the same card-and-detail pattern is shared across staff bookings, staff booking history and customer My Bookings.

## Settled decisions (owner, 2026-11-26)
1. The "All Slots" control is not properly contained (excess width / misaligned arrow icon); fix its sizing and alignment.
2. Each time slot must LIST its entries (a slot can hold many bookings); never collapse them.
3. Each entry shows key details and clearly labels the service type — **Ceramic vs Powder coating**.
4. Tap an entry → detail view (reuse the shared `ReportDetails` popup). Action buttons live there. **Edit price** and **Edit service** sit at the **top right** of the detail, alongside the status (e.g. "Pending") and the booking reference.
5. Edit price uses **two input boxes**: (a) current price (read-only / shown) and (b) proposed new price. The current→proposed change is shown consistently in **three places** — staff reports, customer booking history, and staff booking history — for full transparency. The customer view still hides the staff's written reason (per F-024).
6. Edit service → a popup over the current booking, **pre-filled** with what the customer currently avails, offering predefined catalog options to add/remove, and showing a **summary of the change** before confirming.
7. Normalize the staff status/typography fields ("visit scheduled / booked on / approved / completed") so they match Reports. Chosen approach: replace the separate "Approved" field with a single **Status badge** (minor default; owner may override).
8. **Three aligned views:** the new booking card + tap-for-detail design applies consistently to (a) the staff Bookings screen, (b) staff Booking history, and (c) customer My Bookings (F-024) — same card and detail pattern, the ONLY difference being scope (staff sees all bookings; customer sees only their own). Strong mobile layout following F-025 standards.
9. Remove the generic "view same-name bookings" feature. Instead expose a customer's PREVIOUS bookings only within that customer's own context (the Customers detail / booking history), and fix the current "booking groups are unavailable" error.

## User story / goal
As staff, I want a clean, mobile-friendly Bookings screen where each time slot lists every booking with its service type, I can tap any booking to see full details and act on it (edit price with current and new side by side, edit services with a clear before-confirm summary), and I can see a customer's past visits only from that customer's record — not a confusing global name match.

## Scope
- **"All slots" filter control** (`ServerStaffBookings.svelte`): fix the `.slot-filter` / `.filter-options` sizing (remove the oversized `min-width`, contain the dropdown width) and replace the loose `▾` text arrow with the shared chevron/`ActionIcon` so it aligns. There are currently two overlapping style blocks (`.slot-filter-options` and `.filter-options`); consolidate to one.
- **Slot entries:** keep and reinforce the existing per-slot list (`bookingsAt(hour)` → one card per booking). A slot with several bookings shows them all; the "· N booked" count stays.
- **Service type label:** each booking card clearly labels Ceramic vs Powder coating (derive from the booking's services/`coating_options`: service codes `ceramic` and `wheel-colour`/powder). A booking with both shows both. Add a small labelled, icon-supported tag (F-025 style), not just "N services".
- **Detail actions at top right:** in `ReportDetails` (or its staff slot), move **Edit price** and **Edit service** entry points to the top-right header area next to the Status badge and Ref. The editing UIs themselves stay in the body; the top-right buttons scroll/expand to them. Keep the server re-checking every grant.
- **Two-box price edit** (`ServiceLinesEditor.svelte` / `ServerServiceEdits.svelte`): show the current price in a read-only box beside a "Proposed new price" box. The reason field stays (staff-only). This is **UI-only**: `/api/staff/line-price` already receives `expectedCentavos` (current) and `pesos` (proposed), and `herco_private.booking_price_edits` already stores from/to.
- **Edit service popup:** pre-fill the current services (already loaded via `GET /api/booking-services`), let staff add/remove from the predefined catalog, and show a **summary of the change** (added/removed lines and the new total) before the staff confirms. Uses the existing add/remove path (`POST /api/booking-services`).
- **Status typography / badge:** normalize the detail date tiles to the Reports type scale; replace the "Approved" tile with a single **Status badge** (the timestamps for booked/approved/completed remain available but the headline is the Status badge). Apply to `ReportDetails` and `ServerBookingDetails`.
- **Three aligned views:** ensure the staff Bookings cards (`ServerStaffBookingCard` + `ServerBookingPopup`), staff Booking history (`ServerStaffRecords`) and customer My Bookings (F-024, `ServerBookingHistory` + `ServerCustomerBookingPopup`) use the same `BookingCard` + `ReportDetails` pattern, differing only by scope and the customer-hidden fields. F-026 and F-024 reference each other for this shared pattern.
- **Remove same-name feature:** delete the "View same-name bookings" button and `BookingNameGroup.svelte` usage from `ServerStaffRecords.svelte`; expose a customer's previous bookings only inside the Customers detail (the existing `POST /api/staff/customers` `visits` operation, which is already per-customer and authorized). Diagnose and fix the "booking groups are unavailable" error (see below).

## Out of scope
- The powder/ceramic pricing model and categories (F-021, F-022, F-023). Change-request rules (F-006). The customer change-log data slice itself (F-024 owns the new `GET /api/bookings/history`).

## "Booking groups are unavailable" — root cause and fix
- **Root cause:** the message is NOT produced by `src/lib/live/booking-groups.ts` (that file is a pure customer My-Bookings sort helper — no network, no such string). It is produced by `src/lib/live/BookingNameGroup.svelte` (its catch/`!response.ok` fallback), which calls `POST /api/staff/booking-name-groups` → RPC `herco_staff_booking_name_groups`. The "unavailable" text appears when that RPC returns a non-OK status without a usable message (503 on a DB error, or an unparseable body). It is reached from the "View same-name bookings" button on the Records/Booking-history screen (`surface: "history"`), which the RPC gates behind the Booking History grant — a staff member viewing records without that exact grant (or any RPC/grant mismatch) trips the generic error.
- **Fix:** since the feature is being removed, delete the same-name entry points (`ServerStaffRecords.svelte` button + `BookingNameGroup.svelte`) and the `surface: "history"` path. Keep per-customer "previous bookings" in the Customers detail via the already-scoped `POST /api/staff/customers` `visits` operation. If the `customers` directory surface of `herco_staff_booking_name_groups` is still used by the Customers tab, keep only that path and confirm its grant mapping; otherwise retire the RPC. Verify in `tests/database/` that a staff member with Customers access can read a customer's visits and one without it is denied.

## Data model changes
- **None required.** The two-box price edit is UI-only (API + audit already carry current/proposed). No migration unless retiring the `herco_staff_booking_name_groups` RPC is chosen as a drop (then a small migration `202611260005_retire_name_groups.sql` with a `tests/database/` assertion); otherwise code-only.

## Affected files
- `src/lib/live/ServerStaffBookings.svelte` (filter control, slot list, service-type tag).
- `src/lib/shared/ReportDetails.svelte` (top-right actions, Status badge, date-tile typography).
- `src/lib/live/ServerBookingPopup.svelte`, `src/lib/live/ServerServiceEdits.svelte`, `src/lib/shared/ServiceLinesEditor.svelte` (two-box price edit, edit-service summary).
- `src/lib/live/ServerStaffBookingCard.svelte`, `src/lib/shared/BookingCard.svelte` (service-type tag, shared card).
- `src/lib/live/ServerStaffRecords.svelte` (remove same-name button; previous bookings in customer context), `src/lib/live/BookingNameGroup.svelte` (remove history surface / delete), `src/lib/live/ServerBookingDetails.svelte` (status typography).
- `src/lib/shared/records-ui.ts` (a `serviceTypeLabel` helper for Ceramic/Powder).
- Customer side alignment: `src/lib/live/ServerBookingHistory.svelte`, `src/lib/live/ServerCustomerBookingPopup.svelte` (shared with F-024).

## API contract additions/changes
- **No new endpoints for the two-box price edit** — `POST /api/staff/line-price` is unchanged (already current + proposed). Update `api-contract.md` prose only to note the UI now shows both values.
- The three-surface transparency relies on existing/already-planned reads: staff `GET /api/staff/booking-history` (from/to), Reports `ServerBookingChanges`, and the customer `GET /api/bookings/history` added by F-024.
- If `herco_staff_booking_name_groups` history surface is removed, note the retirement in `api-contract.md` under `POST /api/staff/booking-name-groups` (keep the `customers` surface if still used).

## Permissions / security notes
- Every action re-checked on the server by grant; a top-right button is not access control. Edit price needs `adjustPrices` + `viewIncome`; edit services needs `editServices`.
- Customer previous-bookings stay inside the authorized `POST /api/staff/customers` path (staff with Customers access only). Removing the global name match removes a surface where staff could browse unrelated same-named people.
- Keep private evidence, staff reasons and other customers' data out of any customer-facing surface (the customer change log still hides reasons, per F-024).
- Historical price snapshots preserved; the two-box edit still appends an audited change (current→proposed), never rewrites the original.

## Test plan
- Happy: slot with multiple bookings lists all, each tagged Ceramic/Powder; tap → ReportDetails with Edit price / Edit service top-right; price edit shows current (read-only) + proposed; saving records current→proposed and shows in staff reports, staff history and (reason hidden) customer history; edit service pre-fills current services and shows an add/remove summary before confirm.
- Edge: a booking with both ceramic and powder (both tags); slot with zero bookings (open/past/blocked summary); long customer names; proposed price equal to current rejected ("already the price"); edit service with no catalog options.
- Error/permissions: staff without `adjustPrices`/`viewIncome` sees no Edit price (and server 403 if forced); without `editServices` no Edit service; customer cannot see staff reasons; same-name global browse no longer exists.
- Regression: the "booking groups are unavailable" path is gone; Customers tab previous-bookings still works; existing confirm/cancel/reschedule/complete actions; F-024 customer My Bookings still aligned.
- Mobile/e2e: at 360px, the filter control is contained and the arrow aligned; slot list, detail popup, two-box edit and edit-service summary are all usable; full staff flow (open day → tap booking → edit price → edit service → complete) and the three views look consistent, light and dark.

## Dependencies / order
- Build alongside or just after F-024 (they share the card + detail pattern and the three-view alignment). Uses F-025 design standards. Independent of the F-021/F-022/F-023 pricing-model work, but should land after them so the Ceramic/Powder tags reflect the final catalog.

## Owner-confirmed decisions (2026-11-26)
- Q-O approved: keep booked/approved/completed timestamps inside the detail, smaller beneath the Status badge.
- Q-P approved: use short Ceramic / Powder / Ceramic + Powder tags with an icon.
- Q-Q approved: keep the Customers directory grouping; remove only the global same-name button.

## Added scope — inclusive 5 PM last booking (owner approved 2026-11-27)
- **Decision:** the owner confirmed the shop's closing hour (currently 5 PM) must itself be a bookable slot. Today availability stops at 4 PM (the last slot starts at `closeHour - 1`, so `closeHour = 17` yields a last slot of 16:00). After this change the last bookable slot is the closing hour itself (5 PM bookable when `closeHour = 17`).
- **Not UI-only.** This changes slot generation on the server (availability RPC, staff day view `slots`, calendar `hours`, booking-hour validation "hour must be open", outside-hours counts, and the `GET /api/shop-hours` / `/api/availability` contract text that says "last slot starts at `closeHour - 1`"). Plan it as a deliberate, backward-compatible change with its own migration (e.g. `202611260006_inclusive_closing_slot.sql`) and `tests/database/` assertions. Existing bookings are unaffected; no booking is moved or re-priced.
- **Must not break:** schedule-settings save, outside-hours warnings, blocked/past-slot handling, and existing availability for already-booked hours. Keep the admin's stored `openHour`/`closeHour` meaning intact (only the derived last-bookable-slot rule changes); confirm whether validated hour ranges (`9`–`16`) need to widen to include the closing hour.
- The "finished-product proof panel" (F-009-tied) extension was **declined** for this round (owner 2026-11-27); not in scope.

## Ready checklist (no code until all are ticked and the owner approves)
- [x] Every user step is written out
- [x] Rules, limits and permissions are decided (Q-O–Q-Q defaults approved)
- [x] Screens and their states are described
- [x] Data and API are designed (UI-only; optional retire migration)
- [x] Edge cases and "must not break" are listed
- [x] Acceptance tests are written
- [x] No open questions left (Q-O, Q-P, Q-Q defaults approved 2026-11-26)
- [x] **Owner approved:** 2026-11-26
