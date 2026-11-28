# F-023: Ceramic coating — modern revamp, add-on cards, clearer copy, per-bike pricing reuse

**Status:** Ready (owner approved 2026-11-26) · **Milestone:** M2 · **Depends on:** F-021, F-022

## In one sentence
Give the ceramic booking screen a full modern visual revamp: multi-select add-on cards (checkboxes), "2–5 years with proper care" shown once in green, a clear "◷ 2–3 hours turnover · wait at shop or pick up later" line, and staff managing ceramic bike prices with the same add-bikes + per-bike-price mechanism built for powder.

## Settled decisions (owner)
7. Ceramic add-ons shown as selectable cards; "2–5 years with proper care" shown **once** and coloured **green**; clearer turnover line "◷ 2–3 hours turnover · wait at shop or pick up later"; staff side **reuses the same add-bikes + per-bike-price mechanism** from the powder pricing work (F-021).
- Q-I resolved: add-ons are **multi-select (checkboxes)** — the customer can pick several, not just one.
- **Modern visual revamp (owner):** the current ceramic design is bland/old — this feature must deliver a modern look (modern cards, clear labels, icons, visual segmentation), following the same standards as the F-025 design-polish pass and the `ui-standards` skill. This is an explicit goal, not optional.
- Q-J resolved (default): the wording "2–5 years with proper care" and "2–3 hours turnover · wait at shop or pick up later" is final unless the owner supplies new copy.

## User story / goal
As a customer booking ceramic, I want a modern, clear screen with tappable multi-select add-on cards and plain wording about warranty and turnaround. As staff, I want to add ceramic-eligible bikes and set per-bike ceramic prices in the same Pricing tab, the same way as powder.

## Scope
- Customer: render `ceramicAddons` (from `bookingCatalog.ts`) as modern **multi-select checkbox cards** (pick any number) instead of plain text.
- Full modern revamp of the ceramic block: modern card layout, clear labels, icons, visual separation/segmentation — coordinated with F-025 standards so the two stay consistent.
- Replace the hardcoded copy in the ceramic block: show "2–5 years with proper care" once, styled green (accessible contrast in both themes); show one clear turnover line "◷ 2–3 hours turnover · wait at shop or pick up later". Remove duplicate/repeated copy.
- Staff: ceramic bikes and per-bike ceramic prices use the F-021 add-bikes + exceptions mechanism (ceramic is service code `ceramic`). No separate ceramic pricing engine.

## Out of scope
- Powder categories/booking (F-021, F-022). Polish of non-ceramic components (F-025) — though this screen follows the same visual standards.

## Data model changes
- None beyond F-021. Ceramic reuses the same `ui_pricing` base/exception + bike-tier structures (service `ceramic`). If ceramic needs its own bike-tier list, add it to the F-021 config shape rather than a new table.

## Affected files
- `src/lib/shared/bookingCatalog.ts` (`ceramicAddons`), the ceramic block in `src/lib/live/ServerBookingCatalog.svelte` and any shared ceramic components, shared card styles reused for the add-on and layout cards.
- Staff: `src/lib/live/ServerCatalogPricing.svelte` (ceramic bikes/prices via the shared mechanism).

## API contract additions/changes
- No new endpoints. `coating.ui_catalog` for ceramic may carry the selected add-on ids (an array, since multi-select); document the field under `POST /api/coating-estimate` in `api-contract.md`. Ceramic still uses the actual bike model to determine eligibility (unchanged).

## Permissions / security notes
- Verified-customer booking path unchanged; server re-prices ceramic from the one config. Staff pricing writes enforced by `pricing_grants`.
- Historical ceramic booking snapshots preserved.

## Test plan
- Happy: multiple add-on cards select/deselect (checkboxes); price updates for each combination; warranty line shows once in green; turnover line reads clearly; staff add a ceramic bike + per-bike price and the booking screen reflects it; the revamped screen looks modern (card/label/icon review).
- Edge: no add-on selected; all add-ons selected; add-on card keyboard-accessible; green text passes contrast in light and dark; long add-on labels.
- Error: unverified customer refused; staff without pricing grant refused.
- Regression: existing ceramic bookings reprice/open; mixed ceramic+powder; ceramic eligibility by model still enforced.
- E2e: full ceramic booking with several add-ons at 360px, both themes.

## Dependencies / order
- After F-021 (shared pricing mechanism) and F-022. Coordinate visual standards with F-025.

## Open questions for the owner
- None blocking. (Q-I multi-select checkboxes, Q-J copy final — both resolved 2026-11-26. New: modern revamp is a confirmed goal.)

## Shared appointment-time revision — owner confirmed 2026-11-26

- Follow F-026's inclusive **Last booking time** revision and F-002 rules. Ceramic and mixed-service appointments include **5 PM as the current final start**. The 2–3-hour turnover estimate must not remove this appointment or turn it into a completion deadline.
- Staff-managed default/date hours, blocks and server validation drive customer choices. Acceptance: 5 PM succeeds when open, 6 PM is refused under the current schedule, staff changes and date overrides appear, and old bookings remain unchanged.

## Cross-feature release reminders — 2026-11-27

- Ceramic/mixed bookings share the same protected, bounded booking path and price-snapshot rules. Customer ceramic UI must not expose staff proof; turnover copy does not alter the proof lifecycle.
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
