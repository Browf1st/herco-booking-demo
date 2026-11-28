# F-024: My Bookings redesign — Actions menu, richer cards, full detail, customer change log

**Status:** Ready (owner approved 2026-11-26) · **Milestone:** M2 · **Depends on:** F-006, F-007, F-001 · **Shared pattern with:** F-026 (same card + detail design across the three views)

## In one sentence
Rework the customer My Bookings screen: one red-themed Actions menu per card instead of three buttons; richer labelled, segmented, icon-supported cards; tapping a card opens the full ReportDetails popup (same as staff Reports); and the detail popup shows the full change log with price change (old→new), actor (You vs Shop) and timestamp — no staff reasons, mobile-friendly.

## Settled decisions (owner)
6. Consolidate the three per-card buttons into one **Actions menu** styled in the app's **red theme**; richer, labelled, segmented, icon-supported cards; **tap a card opens FULL detail** via the same `ReportDetails` popup as Reports; show services + inclusions + the change log with peso amounts, actor (You vs Shop) and timestamp; mobile-friendly.
5. Q-K / Q-12 resolved: in the customer change log, **hide the staff's written reason**. Show only the **price change (old → new), actor (You vs Shop), and timestamp**. Staff still see reasons in their own history.
- Q-L resolved (default): Actions menu items are **Reschedule, Cancel, Withdraw request, View details**, shown only where allowed.
- **Three aligned views (shared with F-026):** this customer My Bookings card + tap-for-detail design is the SAME card and `ReportDetails` pattern used by the staff Bookings screen and staff Booking history (F-026). The only difference is scope — the customer sees only their own bookings and never staff-only fields (reasons, names, private notes, contact rows). F-024 and F-026 reference each other; a change to the shared `BookingCard` / `ReportDetails` must keep all three views consistent.

## User story / goal
As a customer, I want a clean card with one Actions menu, and when I tap it I want to see everything about my booking — services, inclusions, and every price/service change with the amount, who made it (me or the shop), and when.

## Scope
- Card: one Actions menu (red theme) replacing the current separate Reschedule / Cancel / View details buttons. Menu items (Reschedule, Cancel, Withdraw request, View details) show only where allowed (reschedule/cancel on future Pending/Confirmed; withdraw when a request is open; view details always). Cards are segmented with clear labels and icons (status, date/time, bike, services count, reference, estimate).
- Tapping the card opens the shared `ReportDetails.svelte` popup (customer variant) — already the path since 2026-11-24; this feature enriches it. The shared card/detail pattern is aligned with F-026 (staff bookings + booking history), scope-only differences.
- Detail popup shows: services + inclusions, totals (original struck through when the shop changed it), and a **customer-facing change log** with each change's **price (from → to pesos), actor shown as "You" or "Shop", and timestamp (Philippine time)**. **No staff-written reason, no staff name, no private notes.** The from→to amounts are exactly the current→proposed values the staff two-box price edit records (F-026); the customer simply never sees the reason.
- The change log is a customer-safe slice of the staff audit (`herco_booking_price_edits`, `booking_service_changes`, `booking_price_corrections`) — WITH amounts, actor collapsed to You/Shop, reasons and names stripped.
- Mobile-first: Actions menu and popup usable at 360px; menu closes on outside tap / Esc / phone Back (consistent with existing behaviour). Follows F-025 design standards.

## Out of scope
- Staff-side history screens and the staff booking revamp (F-026). Change-request rules/limits (F-006 open Q-08). General non-My-Bookings polish (F-025).

## Data model changes
- None expected: reuse `herco_booking_history`. Add a **customer-safe mode** (or a new RPC `herco_customer_booking_history`) that the booking's owner may call, returning amounts but mapping actor to `"you"`/`"shop"` and **stripping staff names, reasons and private notes**. If a new RPC is needed: migration `202611260004_customer_booking_history.sql` with a `tests/database/` assertion (owner allowed; other customer denied; staff name and reason never leaked).

## Affected files
- `src/routes/my-bookings/+page.svelte`, `src/lib/live/ServerBookingHistory.svelte` (cards + Actions menu), `src/lib/live/ServerCustomerBookingPopup.svelte`, `src/lib/shared/ReportDetails.svelte` (customer change-log section; shared with F-026), `src/lib/live/ServerBookingActivity.svelte` (may be superseded by the richer log).
- Server: `herco_booking_history` / new `herco_customer_booking_history` RPC, `src/routes/api/...` endpoint.

## API contract additions/changes
- **New** `GET /api/bookings/history?booking=<uuid>` (customer-safe): who = signed-in customer who owns the booking (database-enforced, `404`/`403` otherwise). Returns `{ booking_id, entries }` where each entry has `at` (ISO), `kind` (`price_changed|price_corrected|service_added|service_removed|booked|approved|completed|cancelled|rescheduled`), `actor` = `"you"|"shop"`, and (for price/service kinds) `from_centavos`/`to_centavos` and `service_label`. **Never** includes staff names, change reasons, private notes, phone/email. Document in `api-contract.md` under Bookings (customer).
- Distinct from staff `GET /api/staff/booking-history` (keeps staff names, reasons, `viewIncome` gating).

## Permissions / security notes
- Only the booking owner can read their history (checked in the RPC; route reports `403`/`404`). Response `private, no-store`.
- Keep private evidence, Auth, staff names, staff reasons, notes and other customers' data out of the customer response. Amounts are the customer's own booking amounts (allowed).
- No change to how changes are written; this only exposes a safe read slice.

## Test plan
- Happy: owner opens a booking with staff price edits and sees each change with from/to pesos, "You"/"Shop", and timestamp (and NO reason text); a service added by staff shows with its price.
- Edge: booking with no changes (empty log state); very long log (cap, e.g. latest 200); booking edited by both customer and staff; original-struck-through total correct.
- Error/permissions: customer A cannot read customer B's history via direct API; unsigned request `401`; staff name and reason never appear in the customer response (assert in db test).
- Regression: existing My Bookings sections/flows, withdraw, edit services, the shared ReportDetails staff variant unchanged (staff still see reasons); the three views stay consistent (F-026).
- E2e: tap card → popup → change log, at 360px, light and dark; Actions menu open/close via tap-away, Esc, phone Back.

## Dependencies / order
- After F-021–F-023 (so price/service changes from the new pricing path show correctly). Builds the shared card + detail pattern together with F-026; can run parallel to F-025.

## Hosted release step (owner authorization required)
- If a new RPC/migration (`202611260004`) is added, apply to hosted Supabase with owner approval before the Worker release.

## Open questions for the owner
- None blocking. (Q-K hide staff reason, Q-L Actions-menu items — both resolved 2026-11-26.)

## Shared appointment-time revision — owner confirmed 2026-11-26

- Customer reschedule requests follow F-002/F-026 staff-managed effective hours, including **5 PM as the current final appointment start**, inclusive. Staff may change default/date last-booking times; customer choices must reflect those settings.
- Preserve existing booked date/time in cards and details when settings change. Validate current availability again at submit and explain when a selected hour was closed/blocked. Acceptance: request 5 PM, refuse 6 PM under current hours, honor date overrides, reject a stale now-closed time, preserve older bookings after shortening hours.

## Cross-feature release reminders — 2026-11-27

- Customer My Bookings/details/history must omit private proof images, object paths, links and metadata. Existing customer sharing routes/controls must be reconciled with F-009, not merely hidden. Keep permitted text/history separate and preserve historical prices.
- Shared requirement: finished-product proof can be saved while Booked before Complete and viewed only by authorized staff/Admin/Owner (F-009/F-012/F-026); no customer proof access. API/data design must reconcile the existing optional customer photo-sharing path.
- Before release, verify request-abuse controls, protected Admin/Owner/data access and performance (F-016), database plus linked-photo backups/recovery (F-015), independent incident email to **elijahpayoc12@gmail.com** (F-027), and preserved historical transaction prices (F-004/F-021). Each feature verifies its affected paths; provider wiring belongs to the coordinating specs rather than seven duplicate implementations.
- One production application environment. Local fictional verification and disposable isolated recovery checks do not imply standing staging resources. These reminders record requirements, not completed security/performance audits or deployed protection.
- Open release decisions remain visible: proof retention and post-save edit/delete policy; evidence grant/API design; numeric API quotas/provider/budget; backup schedule/retention/destination/recovery targets; monitoring thresholds/provider. Previously Ready feature scope is not silently declared fully designed for these new extensions.

## Ready checklist (no code until all are ticked and the owner approves)
- [x] Every user step is written out
- [x] Rules, limits and permissions are decided
- [x] Screens and their states are described
- [x] Data and API are designed
- [x] Edge cases and "must not break" are listed
- [x] Acceptance tests are written
- [x] No open questions left
- [x] **Owner approved:** 2026-11-26
