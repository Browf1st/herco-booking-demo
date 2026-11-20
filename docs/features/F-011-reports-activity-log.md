# F-011: Reports and activity log
> Documented from existing docs on 2026-11-20 — owner to confirm.

**Status:** Needs answers · **Milestone:** M2 · **Depends on:** F-009, F-012

## In one sentence
The Owner and permitted staff see booking counts, service value and promotion totals, and a log of who did what, so the business can be tracked and checked.

## User steps (exactly how it works)
1. Owner signs in and lands on **Reports** (`/reports`).
2. Picks a date range (Philippine time) and sees booking counts, **Completed service value**, average service value, promo totals and net corrections.
3. Opens **Activity log** (`/activity-log`): module filter, search, labeled entries, date range up to 31 days.

## Rules and details
- Page grants Reports and Activity log; `viewIncome` controls money figures.
- Staff with Reports access alone do not receive final charges in rows, activity or exports.
- "Completed service value" = sum of recorded final service prices for completed work. It is not money collected.
- Post-completion corrections change reports by the difference; a separate net-corrections figure is shown.
- Audit events are saved with the verified actor in the same save as the change.
- Collected revenue: only if an approved source and adjustment rules are supplied. TBD — ask owner (Q-04).
- Report exports and their limits: TBD — ask owner.

## Screens
- `/reports`: date selector, totals, empty range state.
- `/activity-log`: filter, search, date range, paginated entries.

## Data
- Booking events and audit tables; aggregate report functions.

## API
- Report and activity log reads. Paths TBD in api-contract.

## Edge cases and errors
- Range over 31 days on activity log → refused with a message.
- Bookings near midnight → counted by Manila date.

## Must not break
- Historical completed amounts and promotion snapshots (F-004).

## Acceptance tests (all must pass)
- [ ] Totals reconcile with completed bookings in staging.
- [ ] Reports-only staff never receive final charges (direct API too).
- [ ] Non-staff cannot read reports (verified on hosted project).
- [ ] Every staff action appears in the log with actor and time.

## Ready checklist (no code until all are ticked and the owner approves)
- [x] Every user step is written out
- [ ] Rules, limits and permissions are decided
- [ ] Screens and their states are described
- [ ] Data and API are designed
- [ ] Edge cases and "must not break" are listed
- [x] Acceptance tests are written
- [ ] No open questions left
- [ ] **Owner approved:**
