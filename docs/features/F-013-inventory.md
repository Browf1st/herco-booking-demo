# F-013: Inventory and stock exports
> Documented from existing docs on 2026-11-20 — owner to confirm.

**Status:** Testing (opening counts needed) · **Milestone:** M2 · **Depends on:** F-012

## In one sentence
Staff track coating materials and supplies, record stock movements and download stock reports, so the shop knows what it has and what was used.

## User steps (exactly how it works)
1. Staff open **Inventory** (`/inventory`).
2. Add or edit items with optional supplier, storage location, unit cost, billing rate and storage capacity.
3. Record stock movements (in, out, adjustments).
4. Filter stock history by item and date range, then page through the results.

## Rules and details
- Page grant Inventory; action `manageInventory`.
- Ledger-based movements with balance checks; duplicate deductions prevented.
- Movement export: last 30 days by default, up to 366 days per export, max 10,000 rows; permission-checked.
- Opening counts and any import of real records: TBD — ask owner (Q-15).
- Low-stock alerts: TBD — ask owner.

## Screens
- `/inventory`: four stock totals, supply search, category and stock status filters, item form, movement entry, and empty and error states.
- Stock on hand uses a desktop table and phone item cards. Both show the same stock, status, reorder threshold, and available inventory actions.
- Stock history aligns Apply filters with the fields on desktop and places pagination on the right. The screen has no CSV download controls. The existing export endpoint remains available to authorized callers.
- The owner approved this screen update on 2026-11-25.
- Layout rules for this screen (and the details pattern for future screens): [stock-style staff screen layout](../inventory-layout.md).

## Data
- Inventory items, options, movement ledger (migrations exist, incl. `herco_inventory_options_write`; TEST items seeded).

## API
- Inventory read/write and CSV export endpoints. Paths TBD in api-contract.

## Edge cases and errors
- Deduct more than on hand → TBD — ask owner (refuse or allow negative).
- Export range over 366 days → refused.
- Same movement submitted twice → recorded once.

## Must not break
- Booking and completion flows that may use stock.

## Acceptance tests (all must pass)
- [ ] Duplicate deductions apply once.
- [ ] CSV exports respect permissions, date limit and row cap.
- [ ] Staff without Inventory grant are refused.
- [ ] Works at 320px width.

## Ready checklist (no code until all are ticked and the owner approves)
- [x] Every user step is written out
- [ ] Rules, limits and permissions are decided
- [ ] Screens and their states are described
- [ ] Data and API are designed
- [ ] Edge cases and "must not break" are listed
- [x] Acceptance tests are written
- [ ] No open questions left
- [ ] **Owner approved:**
