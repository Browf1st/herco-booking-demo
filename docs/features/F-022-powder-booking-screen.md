# F-022: Powder coating booking screen — categories, photos, Custom quote

**Status:** Ready (owner approved 2026-11-26) · **Milestone:** M2 · **Depends on:** F-021, F-001

## In one sentence
Update the customer powder-coating booking flow to show the four colour categories with real photo swatches for every colour, treat Custom (two-tone) as an always-quote option, drop the Raider/Sniper 15–17" restriction, and fix the "ask for a quote" path so it still shows finish options.

## Settled decisions (owner)
2. Four categories: Basic, Special, Luminous/Prismatic, **Custom** (two-tone, always a shop quote, reference photos, no fixed price).
5. **Remove the Raider/Sniper 15–17" restriction** on both the user screen and the server.
- Default Luminous/Prismatic Big bike price is **₱6,999**; full confirmed base table lives in F-021 decision 5.
- Booking reads the SAME `ui_pricing` config (base + exceptions + colour entries) as the staff Pricing tab (F-021); prices resolve exception → base → quote.
- **Every colour option in each category is shown as a photo swatch** (from the F-021 colour entries / public swatch bucket); where a colour has no photo, a labelled swatch is shown.
- Q-G resolved: label the 15–17" size simply **"15–17 in"** for all bikes (no Raider/Sniper tag).
- Q-H resolved (default): **add a short free-text box** on the Custom category for the customer to describe the two-tone finish they want (helps the shop quote). Optional field.

## User story / goal
As a customer, I want to pick my wheel size, see the colour categories with photo swatches for every colour, choose one, and get an instant price — or request a quote for a custom/two-tone finish — without being blocked by a model restriction.

## Scope
- Booking catalog UI shows the four categories as selectable cards. Within each category, **show every colour as a photo swatch + name** for the chosen size (from F-021 colour entries, public swatch bucket).
- **Custom** category: no price shown; shows the seeded reference photos and a clear "the shop will quote this" message, plus an optional free-text description box (Q-H); submitting books as a quote request.
- Remove the 15–17" Raider/Sniper restriction: delete/loosen `isSeventeenInchBike()` / `canChooseRaiderSniperMags()` gating in `bookingCatalog.ts` and the `BookingMags.svelte` filter so any bike can pick the 15–17" size; label it "15–17 in" (Q-G). Keep size → price resolution working.
- Fix the "ask for a quote" (Not sure / quote) path so finish/colour options still display instead of disappearing.
- Running estimate updates as size/category/colour/extras change; server re-prices before submit (unchanged `priceFingerprint` / `price_changed` flow).

## Out of scope
- The pricing data model and staff tab (F-021). Ceramic (F-023). General design polish beyond this screen (F-025).

## Data model changes
- None new. Server-side: the 15–17" restriction check must be removed from the RPC. Folded into F-021's `202611260001` migration (or a small `202611260003_drop_raider_sniper_restriction.sql` if kept separate during build).

## Affected files
- `src/lib/live/ServerBookingCatalog.svelte`, `src/lib/shared/BookingMags.svelte`, `src/lib/shared/PowderColorPicker.svelte`, `src/lib/shared/PowderColorSwatches.svelte`, `src/lib/shared/bookingCatalog.ts`, `src/lib/live/ui-catalog.ts`.
- Server: `herco_private.supports_seventeen_inch_mags()`, `normalize_coating_options` (`raider_sniper_confirmed` check), `herco_preview_coating_price`.

## API contract additions/changes
- `POST /api/coating-estimate` and `POST /api/bookings` / `POST /api/booking-services`: `coating.ui_catalog` gains category `custom` (quote) and an optional `custom_note` free-text field (short, length-capped). The `raider_sniper_confirmed` field becomes optional/ignored (kept for backward compatibility with old clients and saved bookings). The 15–17" size no longer requires a Raider/Sniper. Update the paragraph in `api-contract.md` under `POST /api/coating-estimate` accordingly (add, don't remove, fields).
- `GET /api/booking-catalog`: returns the four categories with colour entries and public swatch photo paths.

## Permissions / security notes
- Verified-customer path unchanged. Server always re-prices; never trust a client price.
- Historical bookings that carried `raider_sniper_confirmed` or the legacy `prismatic` flag must still reprice/open correctly (snapshots preserved).
- Custom/quote bookings store no fixed price; keep the existing quote handling (estimate open, no amount leaked). `custom_note` is length-capped and treated as plain text.
- Swatch photos come from the public bucket only (no private evidence exposure).

## Test plan
- Happy: each size × each category resolves the right price from F-021 config; every colour shows as a swatch; Custom books as a quote with optional note; extras add up (F-019 extras unaffected).
- Edge: any non-Raider/Sniper bike can now pick 15–17"; Not sure / quote path shows finishes; colour without a photo shows a labelled swatch; Custom note empty vs filled; price changes between estimate and submit → `price_changed` review.
- Error: unverified customer refused; oversized coating object or over-long custom note rejected.
- Regression: F-019 flows, ceramic bookings, mixed ceramic+powder, old bookmarked booking links, old bookings with `raider_sniper_confirmed` still open and reprice.
- E2e: full powder booking (size → category → colour swatch → extras → submit → My Bookings) and a Custom quote booking, at 360px, light and dark.

## Dependencies / order
- After F-021 (needs the config shape, colour entries, swatch bucket and resolution). Before/independent of F-023 and F-024.

## Hosted release step (owner authorization required)
- If the restriction removal needs its own migration, it must be applied to hosted Supabase with owner approval before the Worker release.

## Open questions for the owner
- None blocking. (Q-G "15–17 in" label, Q-H optional Custom note — both resolved 2026-11-26.)

## Shared appointment-time revision — owner confirmed 2026-11-26

- Follow F-026's inclusive **Last booking time** revision and F-002 rules. Current powder/Custom quote appointments include **5 PM as the final start**, not 4 PM. Staff-managed default/date hours and blocks are reflected in customer choices, with server validation again at submission.
- Acceptance: 5 PM succeeds when open, 6 PM is refused under the current schedule, staff changes/date overrides update the picker, and blocked/past final slots remain unavailable. No independent hardcoded cutoff or duration subtraction.

## Cross-feature release reminders — 2026-11-27

- Customer powder/Custom booking never receives private finished-product proof, even for its own booking. Keep duplicate-submit/stale-estimate handling, bounded catalog/estimate calls and immutable saved transaction prices.
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
