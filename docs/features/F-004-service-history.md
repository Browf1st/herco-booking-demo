# F-004: Service change and promotion history
> Documented from existing docs on 2026-11-20 — owner to confirm.

**Status:** Testing · **Milestone:** M2 · **Depends on:** F-001, F-003

## In one sentence
Every booking keeps its original services and prices, and every later change is added as a new record, so the shop and customer can see exactly what changed, who changed it and how the price moved.

## User steps (exactly how it works)
1. A booking is saved with its original service lines, prices, discounts and applied promotion.
2. Staff with `editServices` add or remove a service (e.g. an in-shop add-on).
3. The booking shows what was added/removed, who changed it, and the estimate before and after.
4. Staff with `adjustPrices` can save an exact line price at any stage; a correction after completion is recorded as a difference.

## Rules and details
- Original snapshots are never edited; changes are appended (enforced on the server).
- Unchanged lines keep their saved prices and discounts.
- Save the applied promotion ID and display name with the price snapshot.
- Post-completion corrections keep the original completion amount; reports show a separate net-corrections figure.
- Legacy bookings have no original snapshot or per-service prices; how to display them: TBD — ask owner.

## Screens
- Booking details (staff and customer): change history list with actor, time, before/after estimate. Private notes hidden from customers.

## Data
- Original line-item/price snapshot, service change events, promotion reference and label.

## API
- Staff service-edit and price-adjust endpoints. Paths TBD in api-contract.

## Edge cases and errors
- Repeat of the same edit request → applied once.
- Promotion changed or ended later → old bookings still show the old promotion name.

## Must not break
- Reports (F-011) totals and completed records.

## Acceptance tests (all must pass)
- [ ] An edit shows added/removed lines, actor and before/after estimate.
- [ ] Direct attempts to modify the original snapshot are refused.
- [ ] Applied promotion name shows on old bookings after the promotion changes.
- [ ] Post-completion correction changes reports by the difference only.

## Ready checklist (no code until all are ticked and the owner approves)
- [x] Every user step is written out
- [x] Rules, limits and permissions are decided
- [ ] Screens and their states are described
- [ ] Data and API are designed
- [ ] Edge cases and "must not break" are listed
- [x] Acceptance tests are written
- [ ] No open questions left
- [ ] **Owner approved:**
