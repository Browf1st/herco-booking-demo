# F-003: Coating catalog, pricing rules and promotions
> Documented from existing docs on 2026-11-20 — owner to confirm.

**Status:** Blocked (approved catalog not supplied) · **Milestone:** M2 · **Depends on:** F-012

## In one sentence
Authorized staff maintain the coating services, prices and promotions so every estimate and booking uses trusted, current prices.

## User steps (exactly how it works)
1. Staff open **Staff workspace → Pricing** (`/pricing`).
2. Set base rates per service, then add **Coating price rules**: fixed price, range, or quote-required, optionally for an exact bike model and option combination.
3. New rules start disabled; staff enable them when ready.
4. Staff set one active promotion.
5. Customers see the estimate on `/book` (F-001).

## Rules and details
- Needs `changePricing` / `changePromotions` grants.
- Exact-bike rules beat general rules with the same options. A blank bike name matches any eligible bike.
- No enabled rule → base rate. A quote-required base service lets the shop price unusual setups by hand.
- Each save records the staff member and before/after settings.
- New prices apply only to new work; saved bookings keep their snapshot.
- Demo catalog: four ceramic choices, red Honda ADV/PCX eligibility, powder parts, front/rear mag sizes, category and model pricing.
- Real Philippine catalog and price matrix: TBD — ask owner (Q-05).
- One vs several active promotions: TBD — ask owner (Q-06).

## Screens
- `/pricing`: base rates, rule list with add/edit/enable/disable, promotion settings.
- `/booking-prices`, `/booking-services`: staff views for a booking's lines.

## Data
- Services, price rules, promotions, audit of pricing changes (migrations exist; TEST prices seeded).

## API
- Catalog read and estimate endpoints; staff pricing write endpoints. Paths TBD in api-contract.

## Edge cases and errors
- Price changes after a customer viewed an estimate → customer reviews the new amount.
- Two rules match → exact bike wins.

## Must not break
- Historical booking prices and promotion snapshots (F-004).

## Acceptance tests (all must pass)
- [ ] Approved matrix entered in staging; estimates match it for sample bikes.
- [ ] Changing a price does not change saved bookings.
- [ ] Pricing changes appear in the audit with actor and before/after.
- [ ] Staff without the grant are refused.

## Ready checklist (no code until all are ticked and the owner approves)
- [x] Every user step is written out
- [ ] Rules, limits and permissions are decided
- [ ] Screens and their states are described
- [ ] Data and API are designed
- [ ] Edge cases and "must not break" are listed
- [x] Acceptance tests are written
- [ ] No open questions left
- [ ] **Owner approved:**
