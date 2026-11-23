# F-002: Availability, date overrides and slot blocks
> Documented from existing docs on 2026-11-20 — owner to confirm.

**Status:** Needs answers · **Milestone:** M2 · **Depends on:** F-012

## In one sentence
Authorized staff open or close dates and block hours so customers only see times the shop can actually take.

## User steps (exactly how it works)
1. Staff open **Manage Availability** in the staff workspace (`/admin`).
2. Choose a date: open it, close it, restore regular hours, or block single hours.
3. Use **Unblock** to remove a saved manual block.
4. The public schedule on `/book` updates to show open, full or closed.

## Rules and details
- Needs the `manageSchedule` action grant.
- Closing a date leaves existing appointments in place.
- Elapsed same-day hours (Philippine time) show **Past slot** in both admin views and cannot be newly blocked.
- **Unblock** appears only for a saved manual restriction.
- Overrides, blocks and capacity are enforced inside booking and reschedule saves, not only in the screen.
- Public availability shows open/full/closed only, no names or notes.
- Regular opening hours (owner answer 2026-11-21, Q-07): the admin sets the general opening hours themselves (for example 9 AM to 5 PM), and these become the time slots for every date. Today the hours are fixed in code (hourly slots 9 AM–4 PM, closing 5 PM) and open days are fixed to Wednesday–Sunday with per-date overrides, so an admin-editable "opening hours" setting is new work that needs its own spec section and approval before building.
- Blocking (owner answer 2026-11-21): every slot inside opening hours is bookable unless the admin blocks it; a blocked slot is unavailable to customers until the admin reopens it. This already works (Block / Unblock, date open/close).
- Slot capacity: how many bookings one hour slot can take is still open (Q-07b). Today a slot takes 1 booking and then shows as booked.
- Service duration (owner answer 2026-11-21): not needed. Each booking holds only the hour slot it was booked for; long jobs do not block later slots.

## Screens
- Manage Availability and the staff calendar: date controls, slot list with Past slot labels, Block/Unblock buttons.
- `/book` schedule: open/full/closed states.

## Data
- Date and slot restriction tables with shared atomic controls (migration exists).

## API
- Public availability read; staff date/slot control endpoints. Exact paths TBD in api-contract.

## Edge cases and errors
- A block and a booking race for the same hour → database lock decides; no invalid booking.
- Reschedule approval into a now-closed or full hour → rejected.

## Must not break
- Existing appointments on closed dates; customer booking (F-001).

## Acceptance tests (all must pass)
- [ ] Closing a date keeps its existing appointments.
- [ ] Past hours show Past slot and have no Block button.
- [ ] Unblock only appears for manual blocks.
- [ ] Racing block and booking never leave a booking in a blocked hour.
- [ ] Staff without `manageSchedule` are refused by the server.

## Ready checklist (no code until all are ticked and the owner approves)
- [x] Every user step is written out
- [ ] Rules, limits and permissions are decided
- [ ] Screens and their states are described
- [ ] Data and API are designed
- [x] Edge cases and "must not break" are listed
- [x] Acceptance tests are written
- [ ] No open questions left
- [ ] **Owner approved:**
