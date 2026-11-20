# F-001: Customer booking with live price estimate
> Documented from existing docs on 2026-11-20 — owner to confirm.

**Status:** Testing · **Milestone:** M2 · **Depends on:** F-002, F-003, F-005

## In one sentence
A signed-in customer picks coating services, a date and a time, sees a trusted price estimate, and submits a booking so they don't have to call the shop.

## User steps (exactly how it works)
1. Customer opens `/book` (must be signed in; signed-out visitors see the sign-in gate).
2. Chooses ceramic and/or powder coating in one booking: ceramic finish, powder parts, front/rear wheel sizes, bike model.
3. Sees a server estimate for that bike and those options.
4. Picks a date (calendar) and an open hour (clock control) in Philippine time.
5. Presses **Submit booking**, sees a confirmation, and the booking appears in My Bookings (F-006).

## Rules and details
- Signed-in, verified customers only. Guest booking and account claiming stay off (Q-09).
- The server ignores any totals, discounts, roles or status sent by the browser and recalculates prices.
- Date, opening hours, blocks and capacity are rechecked inside the save step.
- Booking, its original price snapshot, a history event and an email job are saved together or not at all.
- Each submit carries a request ID; a retry with the same ID does not create a second booking.
- If prices changed since the estimate was shown, the customer reviews the new amount and tries again.
- Times shown in Asia/Manila. No payment or deposit screens. Announcements are removed.
- Slot capacity and service duration: TBD — ask owner (Q-07).

## Screens
- `/book`: service options, estimate, calendar and clock pickers, Submit booking; sign-in gate when signed out; validation and "slot no longer available" messages.
- Homepage `/` and Showcase `/preview`: still-photo hero and before/after comparisons leading to Book.

## Data
- Bookings, original line-item and price snapshots, booking events, notification outbox (Supabase migrations).

## API
- `POST /api/bookings`: services/options, contact fields, shop-local date/time, idempotency key → booking ID, status, saved estimate, or validation/conflict error.
- Public availability and catalog endpoints (no names or private notes).

## Edge cases and errors
- Two customers take the last spot at once → one succeeds, the other gets a conflict.
- Double click or network retry → same booking returned.
- Estimate changed between view and submit → refreshed amount shown.
- Email outage → booking still saved.

## Must not break
- Demo UI look and the GitHub Pages demo build. Saved bookings keep their original estimate.

## Acceptance tests (all must pass)
- [ ] Signed-in customer books a free slot and sees confirmation (staging, real Supabase).
- [ ] Two concurrent bookings for the last capacity: only one succeeds.
- [ ] Retrying with the same request ID does not duplicate.
- [ ] Another customer cannot read the booking.
- [ ] No business records remain in browser storage; works at phone width.

## Ready checklist (no code until all are ticked and the owner approves)
- [x] Every user step is written out
- [ ] Rules, limits and permissions are decided
- [ ] Screens and their states are described
- [ ] Data and API are designed
- [x] Edge cases and "must not break" are listed
- [x] Acceptance tests are written
- [ ] No open questions left
- [ ] **Owner approved:**
