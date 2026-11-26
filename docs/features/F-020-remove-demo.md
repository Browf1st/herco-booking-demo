# F-020: Remove the static demo, keep the live app

**Status:** Ready (owner approved 2026-11-26) · **Milestone:** M2 · **Depends on:** none (do first)

## In one sentence
Delete the old GitHub Pages demo (fake sign-in, browser storage) so the app has one code path — the live Supabase + Cloudflare Worker app — while keeping all shared UI and the live app fully working.

## Settled decisions (owner)
- Live app only. The demo is removed as its own first step. `src/lib/shared` stays (the live app uses it). The live app must keep working with no visible change for customers or staff.
- Q-A resolved: **archive** the old demo screenshots and `ui-parity-audit.md` in `docs/` as a static reference (do not delete the reference material).
- Q-B resolved: **take the GitHub Pages site down** after removal (no redirect/notice needed).
- Owner approved retiring obsolete demo-only tests on 2026-11-26; preserve live coverage and tests for reusable shared helpers. Preserve unsaved demo edits in the external backup before removing their files.

## User story / goal
As the owner, I want one app to maintain, not two, so changes can't drift between a demo and the real app and nobody is confused about which is "real".

## Scope
- Delete demo-only code and routes: `src/lib/demo/**` (including `store.svelte.ts`, `operations`, `account`, `staffAccess.svelte.ts`), any `DemoPage.svelte`, and demo-only screens/branches.
- Remove the GitHub Pages build and its workflow (the `BASE_PATH=/Herco` static build, the `build` (static) script if demo-only, and the `.github/workflows` Pages deploy job). Keep the Worker build (`build:worker`) as the only build. Take the published Pages site down (Q-B).
- Remove demo imports from shared/live code. Fix the three known exceptions that read demo state: `shared/AvailabilityCalendar`, `shared/RewardReceipt`, and `live/ServerPoints` (which uses the demo reward helper) — move the small helpers they need into `shared/` or `live/` so nothing imports `demo/`.
- Update docs that describe two builds: `AGENTS.md`, `src/lib/AGENTS.md`, `docs/production-handoff.md`, `docs/engineering-checks.md`. Archive `docs/ui-parity-audit.md` and the demo screenshots as a static reference and note the demo is retired (Q-A).
- Update `scripts/performance-budget.mjs` to drop demo bundle budgets; keep Worker budgets.

## Out of scope
- No visual redesign (that is F-025). No behaviour change to any live screen.
- No change to Supabase schema, RPCs or `/api` endpoints (pure deletion + rewiring of shared helpers).

## Data model changes
- None. No migration.

## Affected files
- Delete: `src/lib/demo/**`, `DemoPage.svelte`, demo routes, GitHub Pages workflow, demo-only npm scripts.
- Edit: `src/lib/shared/AvailabilityCalendar*`, `src/lib/shared/RewardReceipt*`, `src/lib/live/ServerPoints*` (remove demo deps), `src/lib/AGENTS.md`, `AGENTS.md`, `scripts/performance-budget.mjs`, affected `docs/*.md`.

## API contract additions/changes
- None.

## Permissions / security notes
- Removing the demo removes the openly accessible fake Admin/Owner simulation — a security improvement (handoff calls the demo's admin behaviour a simulation, not real authorization).
- Confirm no live route accidentally depended on demo fixtures for data; the live app must read only from `/api/*`.

## Test plan
- `npm run check` (svelte-check 0 errors), `npm test` (whole suite green), and the Worker build + size budgets pass. (The "both builds" rule is retired by this feature; after this, only the Worker build exists.)
- Grep proof: no remaining import of `#lib/demo` or `src/lib/demo` anywhere.
- Regression: every live screen (book, my-bookings, account, points, showcase, staff workspace tabs) loads and works locally after the demo is gone; shared components still render (AvailabilityCalendar, RewardReceipt).
- E2e: customer sign in → book → my bookings; staff sign in → bookings/reports — all still work.

## Dependencies / order
- First of this batch. F-021–F-025 assume one code path. Verify F-020 before starting downstream features.

## Open questions for the owner
- None. (Q-A archive, Q-B take down — both resolved 2026-11-26.)

## Ready checklist (no code until all are ticked and the owner approves)
- [x] Every user step / scope item is written out
- [x] Rules, limits and permissions are decided
- [x] Screens and their states are described (deletion only)
- [x] Data and API are designed (none)
- [x] Edge cases and "must not break" are listed
- [x] Acceptance tests are written
- [x] No open questions left
- [x] **Owner approved:** 2026-11-26
