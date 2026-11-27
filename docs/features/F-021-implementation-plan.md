# F-021 Implementation Plan — Powder pricing model (one source of truth)

Status: plan for build. Authoritative spec: `docs/features/F-021-powder-pricing-model.md`. No production code until built under /build.
Hand-off split: database-expert owns the two migrations + test SQL; backend-developer owns the two `+server.ts` routes and `api-contract.md`; frontend-developer owns `ServerCatalogPricing.svelte` + shared model.

Key fact confirmed from the code (drives everything): `herco_private.coating_price_lines(base_lines,bike,options)` (migration `202611190033`) is the live resolver. When `options->'ui_catalog'` is present it prices powder from `config->'powder'->...`; when absent it falls back to `coating_price_lines_legacy` (migration `202611190028`), and **only that legacy branch reads `herco_private.coating_price_rules`**. So the new powder model is built inside the `ui_catalog`-present branch, and retiring `coating_price_rules` only touches the legacy branch. `coating_price_lines` is called from `apply_configured_coating_prices` (create + walk-in configured RPCs) and from `herco_save_booked_services_configured` (edit) — both re-price new/edited work only; saved snapshots in `original_services` / `current_services` are never rewritten by these paths.

---

## 1. New `ui_pricing.config` JSONB shape

Extend the existing singleton `herco_private.ui_pricing.config` (do NOT create a new table). Keep existing `ceramic` and `powder` keys working unchanged (ceramic path and F-023 both still read `config->'ceramic'`). Add a sibling `powderModel` object so the legacy `powder.wheelRates/prismatic/parts/extras/largeSwingarm` keys stay valid and untouched during the transition (parts/extras are still priced from `config->'powder'`; only the colour×size wheel price moves into `powderModel`).

```jsonc
"powderModel": {
  "categories": ["basic","special","luminous-prismatic","custom"],   // fixed set, custom always quote-only
  "baseTable": {            // centavos-free: pesos as numbers, like the rest of ui_pricing (valid_price_tree)
    "basic":              { "10-14": 2199, "17": 3199, "big-bike": 4499, "not-sure": null },
    "special":            { "10-14": 2499, "17": 3499, "big-bike": 5499, "not-sure": null },
    "luminous-prismatic": { "10-14": 2999, "17": 3999, "big-bike": 6999, "not-sure": null },
    "custom":             { "10-14": null, "17": null, "big-bike": null, "not-sure": null }   // all quote
  },
  "colorEntries": [
    { "id": "<uuid>", "name": "Snow White", "category": "basic", "photoPath": null, "quoteOnly": false },
    { "id": "<uuid>", "name": "Fire Blue",  "category": "special", "photoPath": "entry/<uuid>.webp", "quoteOnly": false, "pricesBySize": { "10-14": 2699 } }
    // pricesBySize optional per-size override; absent sizes inherit baseTable[category][size]
  ],
  "exceptions": [
    { "id": "<uuid>", "bikeKey": "honda pcx160", "finish": "<colorId-or-name>", "fromFinish": "matte",
      "priceCentavos": 350000, "quoteOnly": false, "enabled": true, "note": "2026 matte→glossy special" }
    // exactly one of priceCentavos / quoteOnly:true is meaningful; priceCentavos is centavos (integer) to match exception precision
  ],
  "bikeTiers": { "honda pcx160": "big-bike", "yamaha mio gravis": "10-14" }   // bikeKey -> size key
}
```

Rules encoded:
- Sizes fixed: `10-14`, `17` (UI label "15–17 in"), `big-bike`, `not-sure` (always quote).
- Seed the 7 Basic names (decision 6: black, white, glossy black, snow white, matte black, crystal black, pristine white) as `category:"basic"`; every other seeded colour `category:"special"`.
- `custom` baseTable row is all-null → always quote; `category:"custom"` colour entries ignore `pricesBySize` and resolve to quote.
- `bikeKey` and `finish` text are normalised `lower(btrim())` on both write and lookup (matches the existing `coating_price_rules.bike_key` convention).

Coexistence with ceramic / F-023: the `exceptions` + `bikeTiers` mechanism is generic. F-023 (ceramic) reuses the same two arrays but keyed by an added `service` field on exceptions (default `"wheel-colour"` for powder; F-023 adds `"ceramic"`). Add `service` to the exception object now (default/validate to `"wheel-colour"`) so F-023 is additive and needs no shape change.

## 2. Validation + resolution RPCs

`herco_staff_ui_pricing()` — unchanged signature; it already returns `config`, `revision`, `canEdit`. The extended `config` flows through automatically.

`herco_save_ui_pricing(request_id,expected_revision,configuration)` — extend the guard clause (currently requires `ceramic`+`powder` keys). Add, still raising `22023` "Check the coating rates." on failure:
- `configuration ? 'powderModel'` and it is an object.
- `categories` equals exactly `["basic","special","luminous-prismatic","custom"]`.
- `baseTable` has all four category rows; each row has keys `10-14,17,big-bike,not-sure`; every non-null value passes `herco_private.valid_price_tree` (reuse it) and is ≥ 0; `custom` row and every `not-sure` cell must be null (quote-only).
- `colorEntries`: array; each `id` uuid, `name` 1–80 chars, `category` ∈ the four, `photoPath` null or `text` ≤ 200 and matching `^entry/[0-9a-f-]{36}\.(webp|jpg|png)$` (never an absolute or completion-bucket path), `quoteOnly` boolean, optional `pricesBySize` object with only valid size keys + `valid_price_tree` values; `category='custom'` ⇒ force quote (reject non-quote).
- `exceptions`: array; each `id` uuid, `bikeKey` = `lower(btrim)` ≤ 120, `finish` 1–100, `fromFinish` null or ≤ 100, `enabled` boolean, `note` ≤ 200, `service` ∈ {`wheel-colour`} (F-023 adds ceramic); exactly one of (`priceCentavos` non-negative integer) or (`quoteOnly` true); reject duplicates on `(service,bikeKey,finish,coalesce(fromFinish,''))`.
- `bikeTiers`: object, each value a valid size key.
- Keep the existing revision bump, advisory lock, request-id replay and `ui_pricing_audit` write exactly as-is.

Resolution (single path) — extend the `wheel-colour` branch of `herco_private.coating_price_lines` (new migration replaces the function, renaming the current body to `..._v2_legacy` is unnecessary — just `create or replace`). New order for each `Wheels / mags` line:
1. Derive `size`: prefer `config->'powderModel'->'bikeTiers'->lower(bike)`; else map the incoming `c->>'wheel_type'` label to a size key (`10–14 inches`→`10-14`, `17 inches...`→`17`, `Big bike...`→`big-bike`, `Not sure`/empty→`not-sure`). Accept raw size keys too (forward-compat with F-022).
2. Derive `category`: look up `finish` (`c->>'finish'`) in `colorEntries` by id or `lower(name)`; default category `special` if unknown and finish non-empty; empty finish ⇒ treat as quote.
3. **Exception** first: find enabled exception where `service='wheel-colour'`, `bikeKey=lower(bike)`, `finish` matches the colour id/name, and `fromFinish` matches (or is null). If found → its `priceCentavos` (or quote).
4. Else **base**: `colorEntry.pricesBySize[size]` if present, else `baseTable[category][size]`. Null/`not-sure`/`custom` → quote (`ui_component_price(...,null,...)` already yields `quote_required:true`).
5. Feed each resolved rate through the existing `herco_private.ui_component_price(code,label,rate,promo)` so discounts/promo snapshots and the `price_centavos/max_centavos/quote_required` shape stay identical to today. Non-wheel powder parts and extras keep pricing from `config->'powder'` unchanged.

`herco_booking_ui_catalog()` — add `powderModel` to what it returns (it returns the whole `config` already, so colour entries/photos/base table reach the booking screen automatically; confirm no private fields are added — `powderModel` is marketing data only). Keep the verified-customer guard.

`herco_preview_coating_price`, `herco_create_booking_configured`, `herco_create_walk_in_booking_configured`, `herco_create_staff_booking_configured`, `herco_save_booked_services_configured` — **no signature change**; they call `coating_price_lines` and inherit the new resolution.

## 3. Migration plan (two files, ordered, idempotent)

`supabase/migrations/202611260001_powder_pricing_model.sql`
- `begin; ... commit;` plus `notify pgrst,'reload schema';` at end (matches `202611190035`).
- `update herco_private.ui_pricing set config = config || jsonb_build_object('powderModel', <seeded object>), revision = revision+1 where singleton and not (config ? 'powderModel');` — idempotent (guarded by `not config ? 'powderModel'`), seeds decision-5 base table + decision-6 Basic colours + other seeded colours as Special.
- `create or replace` the three functions: `herco_save_ui_pricing`, `herco_coating... ` No — only `herco_save_ui_pricing` (new validation), `herco_private.coating_price_lines` (new resolution), and `herco_booking_ui_catalog` (unchanged body is fine; re-create only if needed). Re-grant exactly as the originals do.
- Colour-photo path field already lives inside `colorEntries[].photoPath` (JSON) — no column needed.
- Keep `coating_price_rules` + legacy branch intact in this migration (retired separately in 0002) so this migration is independently safe.

`supabase/migrations/202611260002_retire_coating_price_rules.sql`
- `begin; ... commit;`.
- Migrate still-wanted active rules: `insert` into `powderModel.exceptions` from `select * from herco_private.coating_price_rules where enabled` — one-off transform in SQL (map `service_code`, `bike_key`→`bikeKey`, derive `finish`/`fromFinish` from `option_match`, `minimum_centavos`→`priceCentavos`, `quote_required`→`quoteOnly`). Append via `jsonb` update; idempotent guard: skip if an exception with a matching `note:'migrated:'||id` already exists.
- Stop the legacy dispatch: `create or replace function herco_private.coating_price_lines_legacy` to no longer `select ... from herco_private.coating_price_rules`; instead return `base_lines` unpriced (or route to the new model). Confirm (grep already done) the **only** live readers of the table are `coating_price_lines_legacy`; `apply_configured_coating_prices` (0028 version) and `herco_save_booked_services_configured` call `coating_price_lines`, not the table.
- `drop table herco_private.coating_price_rules;` then `drop function herco_private.coating_price_lines_legacy` if fully unreferenced, and drop `public.herco_coating_rules` / `public.herco_save_coating_rule`. Saved bookings are unaffected: `original_services`/`current_services` snapshots are self-contained JSON (`coating_options`), never a live join to the table — verified in `herco_booked_services` and the staff-price-edits fixtures.
- `notify pgrst,'reload schema';`.
- Ordering: 0001 before 0002 (0002 reads the `powderModel.exceptions` array 0001 created). Both are append/replace only; never edit a migration that has run.

## 4. Public swatch bucket + color-photo endpoint

New bucket `herco-swatches`, **public** (separate from private `herco-completion`). Created per environment as an owner-authorized release step (flag in the hosted-release section).

New route `src/routes/api/pricing/color-photo/+server.ts` — mirror `src/routes/api/completion/+server.ts` exactly, with these differences:
- `const bucket = 'herco-swatches';` and treat objects as public.
- Guard with the pricing grant, not completion: call a small RPC `herco_pricing_swatch_target(entry uuid)` (new, `security definer`, raises `42501` without `changePricing`, validates the entry id exists in `colorEntries`) to get the upload prefix, same pattern as `herco_completion_upload_target`.
- `PUT /api/pricing/color-photo?entry=<id>`: `requireSameOrigin`, reuse `readPhoto` (≤4 MB) and `photoType` (JPEG/PNG/WebP magic-byte check), path `entry/<id>.<ext>`, `upsert:true` (staff re-upload replaces), returns `{ path }`. After upload, the staff save writes that `path` into the colour entry's `photoPath` via `herco_save_ui_pricing` (frontend stores it in the draft then saves).
- `GET /api/pricing/color-photo?entry=<id>`: public read — resolve the entry's `photoPath` from `herco_booking_ui_catalog`/a light public RPC, download from the public bucket, return the image with `content-type` + `x-content-type-options: nosniff` and `Cache-Control: public, max-age=300`. Never serve a `herco-completion` object through this path (validate the bucket/prefix).
- Build-time seeding (decision 3/scope): a one-off script converts the owner's Downloads swatch folders to web WebP, strips EXIF, uploads to `herco-swatches`, writes `photoPath` on seeded entries. Treat those files as untrusted: read/convert only, never execute from the folder; run any Python with `-I`.

## 5. Staff Pricing tab (`ServerCatalogPricing.svelte`)

Extend the existing `Config` type with `powderModel`; keep ceramic/powder sections as-is. Add sections (all gated by `canEdit`, same disabled/stale/busy pattern, same save flow and 20,000-char limit):
- **Base price grid**: 4 categories × 4 sizes number inputs, pre-filled from `powderModel.baseTable`; `custom` row and `not-sure` column shown as read-only "Quote".
- **Colour-entry manager**: list add/edit/disable; per entry name, category select (4 options), quote-only toggle, optional per-size price overrides, and a photo upload (`PUT /api/pricing/color-photo?entry=<id>` on file pick, store returned `path` into the draft entry's `photoPath`, preview via the `GET` url). New entries get `crypto.randomUUID()` client-side.
- **Bike-to-tier manager**: map a bike key to one size key (`bikeTiers`).
- **Exceptions editor**: add/edit/enable rows: bike key, finish (colour), optional fromFinish, price or quote-only, note — mirrors the retired `CoatingRuleEditor` UX but writes into `powderModel.exceptions`.
- Shared model updates in `src/lib/shared/bookingCatalog.ts` (export category + size constants, size-label map "15–17 in") and `src/lib/live/ui-catalog.ts` (extend `UiCatalogConfig` type with `powderModel`). Remove `CoatingRuleEditor.svelte` and its mount from `src/routes/pricing/+page.svelte`.

## 6. Database tests (`tests/database/`)

New file `tests/database/powder-pricing.sql`, following the `staff-price-edits.sql` pattern (`herco_test_refused`, fixture uuids, `begin;`…`rollback;`, one allowed + one denied actor). Assert:
- Resolution order: seed config; a bike+finish with an enabled exception returns the exception price; a different bike returns `baseTable[category][size]`; `custom` finish returns quote; `not-sure` size returns quote; colour with `pricesBySize` overrides base; disabled exception falls through to base; duplicate exception rejected (`22023`).
- Grants: `herco_save_ui_pricing` and the swatch-target RPC refuse (`42501`) a staff actor without `changePricing`, and a non-staff/anon actor; allow an actor with the grant.
- Swatch bucket public while completion stays private: assert `storage.buckets` has `herco-swatches` with `public=true` and `herco-completion` with `public=false` (if buckets are seeded in migrations/bootstrap; otherwise assert the RPC path separation).
- Dropped table breaks nothing: after the 0002 migration, `herco_create_booking_configured` / `herco_save_booked_services_configured` still price a powder booking; `herco_private.coating_price_rules` no longer exists (`to_regclass` is null); an existing saved booking's `original_services` is byte-identical before and after.
- Historical snapshots preserved: insert a pre-existing booking snapshot, run a price change to the config, assert the booking's `original_services`/`original_total_centavos` unchanged.

## 7. Build sequence + risk notes

1. database-expert: write `202611260001` (shape + validation + resolution + seed). Run `npm run check` / local migration apply. Risk: new validation rejecting the existing config on save — mitigate by seeding `powderModel` in the same migration so the first save already carries it.
2. backend-developer: update `api-contract.md` Pricing section (document `powderModel` sub-shapes on `GET/POST /api/pricing/catalog`; add `PUT/GET /api/pricing/color-photo`; mark `coating-rules` retired `410`/`403`; note `/api/booking-catalog` + `/api/coating-estimate` shapes unchanged to the client). Add fields, never remove. Add the color-photo route + swatch-target RPC.
3. frontend-developer: extend `ServerCatalogPricing.svelte` + shared model; remove `CoatingRuleEditor`. Run Worker build after `shared/` change.
4. Retire migration `202611260002` + the retirement of `/api/pricing/coating-rules` writes (`POST`→`410`/`403`). Do this only after 1–3 land and tests pass, so the new path is proven before the old one is dropped.
5. Build-time swatch seeding script (untrusted files — view/convert only).
6. Run full gate: `npm run check`, `npm test`, `npm run build:worker`, `node scripts/performance-budget.mjs worker`, plus the new DB test.

Immutability guarantees (must-not-break): never write to `original_services`/`original_total_centavos` of existing rows; new prices apply only through `coating_price_lines` on create/edit of new/edited work; the `apply_configured_coating_prices` snapshot behaviour is unchanged. `coating_options` snapshots are self-contained, so dropping `coating_price_rules` cannot alter any historical price. Keep `config->'ceramic'` and `config->'powder'` parts/extras untouched so ceramic (and F-023) and non-wheel powder parts keep working.

## Hosted release (owner-authorized, separate step)
Apply `202611260001` then `202611260002` to the hosted Supabase project; create the public `herco-swatches` bucket on each environment; existing saved prices preserved. Free plan: no backup — flag to owner before applying.
