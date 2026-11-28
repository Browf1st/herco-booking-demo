# F-021: Powder pricing — one source of truth, staff Pricing tab

**Status:** Ready (owner approved 2026-11-26) · **Milestone:** M2 · **Depends on:** F-020, F-003

## In one sentence
Give staff one place to manage powder-coating prices: four colour categories, a base price table (category × bike size), per-bike/finish exceptions that override the base, and staff-added colour entries with photos — all read by the booking screen so changes show up automatically. Retire the old second pricing engine so only one path remains.

## Settled decisions (owner)
1. One pricing source of truth, two layers, both staff-editable in Supabase:
   - (a) **Base table:** price per colour category × bike size.
   - (b) **Exceptions:** per bike + finish override of the base (example: PCX 160 2026 matte→glossy special price).
   - Booking resolves **exception → base → quote**.
2. **Four powder colour categories:** Basic, Special, Luminous/Prismatic, **Custom**. Custom covers two-tone and **always requires a shop quote** (reference photos shown, no fixed price).
3. Staff can **add colour entries** (photo + name), tag each to one of the four categories, set a size-based price or mark it quote-only; and **add bikes** to tiers. Changes reflect automatically on the user booking screen.
4. **Retire the legacy `coating_price_rules` engine — migrate then drop** (Q-C resolved): move any still-wanted legacy rules into per-bike exceptions, then drop the table, preserving all historical booking price snapshots. After this, only `ui_pricing` (base + exceptions + colour entries) is used.
5. **Base prices CONFIRMED as the defaults** (per 10–14" / 15–17" / Big bike; resolves Q-E/Q-05 for powder):
   | Category | 10–14" | 15–17" | Big bike |
   |---|---:|---:|---:|
   | Basic | ₱2,199 | ₱3,199 | ₱4,499 |
   | Special | ₱2,499 | ₱3,499 | ₱5,499 |
   | Luminous/Prismatic | ₱2,999 | ₱3,999 | ₱6,999 |
   | Custom | quote | quote | quote |
6. **Basic colours** = black, white, glossy black, snow white, matte black, crystal black, pristine white. **Anything else = Special** by default (staff can re-tag).
7. Swatch photos go in a **new PUBLIC storage bucket**, separate from the private completion-evidence bucket (Q-D resolved: public bucket, e.g. `herco-swatches`).

## User story / goal
As shop staff, I want to change powder prices, add new colours with photos, add bikes, and set special prices for specific bike+finish combinations, without a developer, and have the booking screen update by itself.

## Scope
- Extend the single pricing config in `herco_private.ui_pricing` (singleton JSONB + revision) to hold:
  - the four categories (fixed set: `basic`, `special`, `luminous-prismatic`, `custom`; `custom` is always quote-only),
  - the base table keyed by `category × size` (sizes: `10-14`, `17` (shown 15–17; no longer Raider/Sniper-restricted — see F-022), `big-bike`, `not-sure`=quote), seeded with the confirmed defaults in decision 5,
  - a list of **colour entries**: `{ id, name, category, photoPath|null, quoteOnly:boolean, pricesBySize? }` (a colour may inherit its category's base prices or carry its own); the seven Basic colour names in decision 6 are seeded as Basic, all other seeded colours default to Special,
  - a list of **exceptions**: `{ id, bikeKey, finish(colour id or name), fromFinish?, priceCentavos|quoteOnly, enabled, note }`,
  - the bike/size tier membership (which bikes belong to which size tier).
- **Initial colour-swatch seeding (build task):** seed colour entries for Special, Luminous and Prismatic from the owner's photo folders:
  - `C:\Users\Brof1st\Downloads\HERCO POWDER COATING-...\HERCO POWDER COATING\MAGS POWDER COAT` → Special/Luminous/Prismatic swatches;
  - `...\CUSTOMIZED MAGS` → Custom reference photos;
  - `926292608_...n.jpg` → the Prismatic list.
  - Read each colour's name from the filename/visible text; where none is readable, label sequentially "Color 1", "Color 2", …. Staff can rename/replace later.
  - SECURITY: these are untrusted downloaded files — **read/view only, never execute anything from those folders**. This runs at F-021 **build time**, not during spec writing. Convert to web-sized WebP, strip camera data, upload to the public swatch bucket, and record the public path on each colour entry.
- Staff Pricing tab (`/pricing` → `ServerCatalogPricing.svelte`) gets: category sections, base price grid (pre-filled with the confirmed defaults), a colour-entry manager (add/edit/disable, upload photo, tag category, set per-size price or quote-only), a bike-to-tier manager, and an exceptions editor.
- Server re-pricing (`herco_preview_coating_price`, booking create/edit RPCs, `coating_price_lines`) resolves exception → base → quote from this one config.
- Retire `coating_price_rules`: migrate any still-wanted rules into exceptions, stop `coating_price_lines` dispatching to it, drop the table, remove `CoatingRuleEditor.svelte` from the Pricing tab, and disable `/api/pricing/coating-rules` writes.

## Out of scope
- The customer booking screen UI (F-022) and ceramic add-ons (F-023) — those consume this model.
- Changing historical booking prices (snapshots stay fixed).

## Data model changes (migrations)
- **`202611260001_powder_pricing_model.sql`**: extend the `ui_pricing` config shape (categories, base table seeded with decision-5 defaults, colour entries seeded per decision 6, exceptions, bike tiers); update RPCs `herco_staff_ui_pricing` / `herco_save_ui_pricing` to read/write and validate the new shape (reject bad rates/ranges; enforce `custom` = quote-only; bump revision). Update `herco_booking_ui_catalog`, `herco_preview_coating_price` and the create/edit booking RPCs to resolve exception → base → quote. Add a public storage path field for colour photos.
- **`202611260002_retire_coating_price_rules.sql`**: migrate active `coating_price_rules` into exceptions, make `coating_price_lines` use only `ui_pricing`, then **drop** `coating_price_rules` (Q-C) after confirming no booking snapshot reads it live (snapshots are self-contained `coating_options`). Add `tests/database/` assertions for the new resolution order and for `pricing_grants` enforcement.
- Permissions: writes require the existing pricing grant (`herco_private.pricing_grants` / `changePricing`); reads of config require pricing grant; the booking read path stays verified-customer. Q-F default: **any staff member with the pricing grant** may add/edit colours and bikes (the grant is already Owner/Admin-controlled via staff access).

## Affected files
- Server/db: `supabase/migrations/202611260001_*.sql`, `202611260002_*.sql`, RPCs above, `src/lib/server/**` pricing helpers, `src/routes/api/pricing/catalog/+server.ts`, `src/routes/api/pricing/coating-rules/+server.ts`, new color-photo endpoint.
- Screens: `src/routes/pricing/+page.svelte`, `src/lib/live/ServerCatalogPricing.svelte`; remove `CoatingRuleEditor.svelte`.
- Shared model: `src/lib/shared/bookingCatalog.ts` (category/size model), `src/lib/live/ui-catalog.ts`.
- Upload: new public swatch bucket + a small server storage helper in `src/lib/server` (reusing the completion upload code pattern, but a different, public bucket).

## API contract additions/changes
- `POST /api/pricing/catalog`: `config` object now carries `categories`, `baseTable`, `colorEntries`, `exceptions`, `bikeTiers`. Still `requestId`, `revision`, 20,000-char limit, `409` on stale revision. Document the new sub-shapes.
- `GET /api/pricing/catalog`: returns the extended config.
- **New** colour-photo upload/read endpoint using the PUBLIC bucket: `PUT /api/pricing/color-photo?entry=<id>` (raw image bytes, ≤4 MB, JPEG/PNG/WebP, staff + pricing grant, same-origin; returns `{ path }`) and `GET /api/pricing/color-photo?entry=<id>` (public swatch image). Swatches are marketing images, served from the public bucket, never the private completion bucket.
- `GET/POST /api/pricing/coating-rules`: **retired** — `POST` returns `410`/`403`. Note the change in `api-contract.md` (add fields, don't silently remove).
- `GET /api/booking-catalog` and `POST /api/coating-estimate`: unchanged shape to the client, but now resolve via the new config; `custom` is a quote category; keep `wheel_color_tier`/`finish` working.

## Permissions / security notes
- All pricing reads/writes enforced by `pricing_grants` inside the RPC (route reports `403`). A hidden button is not access control.
- Colour swatch photos live in a **public** bucket, fully separate from private completion evidence. Keep private completion evidence, Auth and staff data out of every public response. Never serve completion objects through the swatch path.
- Seeding reads untrusted downloaded image files — view/convert only, never execute from those folders; strip camera metadata before upload.
- New prices apply only to new work; existing booking snapshots and historical `coating_options` stay fixed (append audited changes, never rewrite).
- Validate every rate/range server-side; reject negative or non-integer centavos; `custom` must be quote-only.

## Test plan
- Happy: staff set base table (defaults pre-filled match decision 5), add a colour with photo tagged Special, add a bike to the Big-bike tier, add a PCX 160 2026 matte→glossy exception; booking estimate for that bike+finish returns the exception price; another bike returns base; Custom returns quote.
- Seeding: the three category lists (Special/Luminous/Prismatic) are seeded from the owner folders with readable names or "Color N" fallbacks; each swatch has a public photo path; Custom reference photos present.
- Edge: missing photo (swatch fallback), colour with own per-size price vs inherited, exception disabled, `not-sure` size → quote, duplicate exception rejected, oversized/stale config `409`, Basic re-tag to Special.
- Error/permissions: staff without pricing grant refused (`403`) on read, write and photo upload; non-staff refused; legacy `coating-rules` write refused (retired).
- Regression: existing saved bookings keep their prices; F-019 nine prices still resolve; ceramic pricing unaffected; `coating_price_lines` no longer references `coating_price_rules`; dropped table does not break any read.
- Database assertions in `tests/database/` (one allowed, one denied actor) for resolution order, grants, and that swatch bucket is public while completion stays private.
- E2e: staff edit price → customer booking screen shows the new price without a deploy.

## Dependencies / order
- After F-020. This is the keystone; F-022 (booking screen) and F-023 (ceramic) depend on the per-bike exception + add-bike + colour-entry + swatch mechanism built here.

## Hosted release step (owner authorization required)
- Migrations `202611260001` and `202611260002` must be applied to the hosted Supabase project as a separate, owner-authorized release before the updated Worker goes live. The new public swatch bucket must be created on each environment. Existing saved booking prices are preserved. (Free plan: no backup possible — flag to owner.)

## Open questions for the owner
- None blocking. (Q-C migrate+drop, Q-D public bucket, Q-E/Q-05 powder prices confirmed, Q-F any pricing-grant staff — all resolved 2026-11-26.)

## Owner clarification — unnamed Special photos (2026-11-26)

- Owner confirmed unnamed photos from MAGS POWDER COAT may default to **Special**, labelled **Color 1, Color 2, …**, with staff renaming/re-tagging later through the colour-entry manager. Do not block seeding on identifying the exact finish name or invent a manufacturer colour name.
- The local review pack assigns 32 formerly unclassified image files to Special / Color 1–32. These are provisional photo entries, not a claim of 32 distinct verified finishes. One MOV remains a separate reference, not a colour-photo entry. Named Basic/Luminous/Prismatic and Custom references retain their categories.
- Keep per-category IDs stable even if display names change; Special Color 1 and the unnamed Prismatic chart swatch Color 1 are distinct entries. Preserve source-to-copy mappings. Unsupported HEIC/DNG previews need proper web-image conversion during F-021 asset preparation; original-present is distinct from missing-photo. No hosted upload or pricing/config change is performed by organizing the local preview.

## Owner clarification — image display and Prismatic swatches (2026-11-26)

- HEIC/HEIF source photos must appear in the booking/colour preview via browser-compatible converted display copies; an existing source photo must not remain a missing-photo placeholder just because its original format is unsupported. Preserve originals and strip metadata from web assets. Apply the same conversion to any selected DNG reference.
- Extract the seven individual Prismatic samples directly from the supplied chart rather than showing only the whole chart or marking individual samples missing: **Prism Blue, Prism Purple, Prism Teal, Prism Green, Prism Deep Violet, Prism Pink, Prism Bronze**. Owner confirmed the previously unnamed pink sample is **Prism Pink**; it is not Color 1. Retain the original chart as a reference, not an additional selectable finish. Preserve the source colours; no generative replacement of the samples.

## Cross-feature release reminders — 2026-11-27

- Pricing-specific: catalog/base/exception/promotion edits affect new work only; preserve existing transaction amounts and history. Public swatch uploads are not private booking proof. Protect pricing writes, bound uploads/requests and verify unchanged old booking totals.
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
