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
   - Owner-approved layout 2026-11-23: every staff tab uses the shared page header. Booking cards show time and status badge, customer, "Bike · N services", one main button, a "⋯" menu for other actions and a Details button; full details open in one popup sheet (bottom sheet on phones, side panel on desktop) instead of "Tap to view more". Filters apply as they change ("Filters (n)", Reset filters); History cards show date and time.

## Rules and details
- Grants: `confirmBooking`, `cancelBooking`, `rescheduleBooking`, `reviewCancellation`, `reviewReschedule`; pages Bookings, Change requests, Booking history, Customers.
- Dates use Philippine time; This month covers the whole calendar month.
- Private notes stay out of customer views.
- Every action records the verified staff member; repeat requests are applied once.
- Owner lands on Reports; staff without a section grant go to their landing page.

## Price changes and added services after inspection (owner-approved 2026-11-24)
Owner's words: some services need an estimate and the price may change on inspection at the shop, so staff (admin/owner/staff, not only the customer) can edit the price of individual services and add more services; keep logging what the initial price was and what changed, and show the logs in More details.
- **Where:** the More details popup (Reports, Bookings and Booking history), section "Services": each service line gets **Edit price**; a button **Add service** opens the catalog list.
- **When:** only while the booking is Pending or Booked (not Done, not Cancelled). After Done, the existing price correction (`adjustPrices`) stays the way to fix a final price, and it is logged too.
- **Who:** changing a service's price needs the existing grant **Adjust individual booking prices** (`adjustPrices`); adding or removing services needs **Edit booked services** (`editServices`). The Owner has both. Checked in the database.
- **Rules:** new price in whole pesos, 0 to ₱1,000,000; a short reason is required (e.g. "Extra corrosion found"); the original booking snapshot never changes; each change is appended to the booking's history with who, when, old price → new price, and reason; the booking total is the sum of the current lines. Adding a service uses today's catalog price (editable straight away with a reason). Same retry key protection as other saves.
- **Customer edits after a staff price change (owner 2026-11-24):** once staff changed any line price on a booking, the customer can no longer edit its services; My Bookings shows "The shop updated this booking after inspection. Contact the shop to change services." (enforced in the database).
- **Customer:** My Bookings shows the current services and total, with the original total struck through and "Updated by the shop after inspection". No email for now.
- **History in More details:** a "Changes" list, newest first: "Nov 24, 3:10 PM · Admin Elijah · Ceramic coating ₱1,799 → ₱2,300 · Extra corrosion found", "… · Added Helmet coating ₱299", plus status changes (booked, approved, completed, cancelled, rescheduled) already in the booking events.
- **Reports:** completed income still counts only Done bookings (final price); the Price column and the popup show "Price" (not "Estimated service value").
- **Edge cases:** booking becomes Done or Cancelled while the editor is open → save refused "This booking can no longer be changed." (409); two staff edit at once → the later save is refused if the line changed since it was opened, with Reload; negative, blank, over the limit or non-number → 400; staff without the grant → buttons hidden and the server refuses (403).

## Bookings tab details and day schedule (owner 2026-11-24, second batch)
- **Where actions live:** the Bookings tab, not Reports. Clicking a booking in the Bookings day schedule opens the same **More details** popup design as Reports, but with the actions this staff member may use: Approve/Confirm, Reschedule, Cancel, Complete, per-service **Edit price** (most important), **Add service**, **Remove**, and the Changes history. Reports Details is read-only.
- **Add service:** opens the existing booking service picker so staff can add any further services the customer wants (today's catalog prices, then editable with a reason).
- **Day schedule:** each hour (e.g. 9 AM) lists **all** its bookings (no limit per hour), each one clickable to open More details.
- **Slot filter:** the "All slots 8 ▾" control shows a broken arrow character and an unclear "8". Fix the arrow and label the number clearly (e.g. "8 slots").

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
