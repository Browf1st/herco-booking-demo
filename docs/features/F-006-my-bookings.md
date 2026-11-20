# F-006: My Bookings and change requests
> Documented from existing docs on 2026-11-20 — owner to confirm.

**Status:** Needs answers · **Milestone:** M2 · **Depends on:** F-001, F-005

## In one sentence
A signed-in customer sees all their bookings on any device and can ask to cancel or reschedule, which the shop reviews.

## User steps (exactly how it works)
1. Customer opens `/my-bookings`; compact cards show the booking overview and status color.
2. **View details** expands the record inline (services, history, intake signing event).
3. Request buttons at the top of each card: request cancellation or reschedule.
4. Shop reviews the request in the staff queue (F-007) and decides; the customer is emailed (F-014).
5. Customer can withdraw a pending request; the visit stays unchanged.

## Rules and details
- Only the booking owner can see or request changes (checked in database and server).
- Paginated list; only that account's permitted fields; private staff notes never shown.
- Requests stay open for manual handling; sending or skipping an email does not change status.
- Walk-in customers see status and signing event and contact the shop for changes.
- Current build (checked in code 2026-11-20): customers edit services only while a booking is Pending and the visit is in the future; they can request cancel or reschedule on Pending or Confirmed future bookings, one open request at a time. Cancel and reschedule requests email the shop inbox only when one is set (Q-13); service edits send no email. All three are saved as booking events and appear in the staff Activity log (F-011).
- Layout (approved 2026-11-20): section buttons with counts: Upcoming (future Pending and Booked, soonest first), Requests (future booking with an open cancel or reschedule request), Past (completed visits plus past-dated visits the shop never closed, latest first, each with its status badge), Cancelled. Sections appear only after the change-request check finishes; if that check fails, a warning shows and request buttons stay hidden. Each card has a coloured left strip and status badge, the visit date and time first, then services, bike, reference and estimate. Reschedule and cancel buttons only show where allowed; "View details or edit services" only on future Pending bookings. Grouping covers the bookings on the current page. Smaller type than the marketing pages.
- After submitting a booking, the customer lands here with a "Booking submitted" message, the new booking highlighted, and its status (2026-11-20).
- Request expiry, change windows and limits: TBD — ask owner (Q-08).
- Whether the old time stays held during a reschedule review: TBD — ask owner (Q-08).
- Approval note visibility to customers: TBD — ask owner (Q-12).

## Screens
- `/my-bookings`: cards, View details, request buttons, withdraw, empty state ("no bookings yet"), load error.

## Data
- Change requests linked to bookings; booking events.

## API
- `GET /api/my-bookings` (paginated, own bookings only); change-request create and withdraw endpoints. Paths TBD in api-contract.

## Edge cases and errors
- Request on a booking already cancelled or completed → refused.
- Reschedule target becomes full before approval → approval refused.
- Withdraw after staff already decided → refused with a clear message.

## Must not break
- Demo card layout (request controls in header, inline details).

## Acceptance tests (all must pass)
- [ ] Customer A cannot see or request changes on customer B's booking (direct API too).
- [ ] Withdraw leaves the visit unchanged.
- [ ] My Bookings shows the same data after reload and on another device.
- [ ] Works at phone width in both themes.

## Ready checklist (no code until all are ticked and the owner approves)
- [x] Every user step is written out
- [ ] Rules, limits and permissions are decided
- [x] Screens and their states are described
- [ ] Data and API are designed
- [x] Edge cases and "must not break" are listed
- [x] Acceptance tests are written
- [ ] No open questions left
- [ ] **Owner approved:**
