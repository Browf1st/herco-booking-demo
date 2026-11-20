# F-007: Staff booking queue, calendar and booking history
> Documented from existing docs on 2026-11-20 — owner to confirm.

**Status:** Testing · **Milestone:** M2 · **Depends on:** F-002, F-012

## In one sentence
Staff see pending bookings and change requests, confirm, cancel or reschedule them, and search past bookings, so the day's work is organized in one place.

## User steps (exactly how it works)
1. Staff open the workspace (`/admin`); the Booking menu shows counters for pending bookings and change requests.
2. Confirm a pending booking, or review a cancellation/reschedule request and approve or decline it.
3. With separate grants, cancel or reschedule a booking directly.
4. Search the scoped customer directory (`/customers`): expandable records with mobile, email, points and booking history.
5. Open **Booking History** (`/booking-history`): date filter (Today default, This month, Specific date, Custom range, All dates), clickable status counts, search, 10 per page.

## Rules and details
- Grants: `confirmBooking`, `cancelBooking`, `rescheduleBooking`, `reviewCancellation`, `reviewReschedule`; pages Bookings, Change requests, Booking history, Customers.
- Dates use Philippine time; This month covers the whole calendar month.
- Private notes stay out of customer views.
- Every action records the verified staff member; repeat requests are applied once.
- Owner lands on Reports; staff without a section grant go to their landing page.

## Screens
- Staff calendar/queue, pending counters, request review dialogs.
- Booking History: summary cards, search/date/status panel, responsive rows, empty state with "View all bookings", invalid-range message.

## Data
- Bookings, change requests, booking events; `herco_staff_pending_counts`.

## API
- `/api/staff/counts`; staff booking action endpoints. Full list TBD in api-contract.

## Edge cases and errors
- Approving a reschedule into a now-full hour → refused.
- Revoked grant with page still open → next action refused.
- Empty search or date range → clear empty state.

## Must not break
- Demo look (calendar, tiles, modals) per docs/ui-parity-audit.md.

## Acceptance tests (all must pass)
- [ ] Counters match pending bookings and requests.
- [ ] Each action works with its grant and is refused without it (direct API too).
- [ ] Manila vs US date boundaries filter correctly.
- [ ] Works at 320/390/768/1440px in both themes without sideways scrolling.

## Ready checklist (no code until all are ticked and the owner approves)
- [x] Every user step is written out
- [x] Rules, limits and permissions are decided
- [x] Screens and their states are described
- [ ] Data and API are designed
- [x] Edge cases and "must not break" are listed
- [x] Acceptance tests are written
- [ ] No open questions left
- [ ] **Owner approved:**
