# F-025: Design polish — labels, icons, segmentation across shared components

**Status:** Ready (owner approved 2026-11-26) · **Milestone:** M2 · **Depends on:** F-020, F-022, F-023, F-024

## In one sentence
A cross-cutting visual polish of the shared components so screens use real labels, icons, and clear visual separation/segmentation — killing the "text noise" look — consistently across the live app.

## Settled decisions (owner)
8. Cross-cutting design polish of shared components: real labels, icons, visual separation/segmentation to reduce "text noise".
- Q-M resolved (default): use the icon style already present in `src/lib/shared` (outline SVGs), adding new icons only where a clear one is missing, keeping the bundle within budget.
- Q-N resolved (default): no single screen singled out — apply the standards everywhere; the ceramic screen (F-023) and My Bookings (F-024) already carry the same modern standards, so this pass keeps the rest consistent with them.

## User story / goal
As a customer or staff member, I want screens that look organised — each piece of information has a clear label and icon and is visually grouped — instead of walls of plain text.

## Scope
- Audit shared components used across booking, My Bookings, and staff screens (`src/lib/shared/**` and the `live/Server*` wrappers) for: missing labels, label+value pairs run together, lack of icons, and sections that need visual separation (cards, dividers, segmented groups).
- Apply consistent patterns: labelled fields, an icon set, segmented/card grouping, spacing scale, and the app's red accent used consistently. Keep consistency with the F-023 ceramic revamp and F-024 My Bookings cards.
- Follow the `ui-standards` skill (simple, modern, accessible) and `frontend-performance` (no bundle bloat from icons; prefer inline SVG already used).
- Keep it visual only — no behaviour or data changes.

## Out of scope
- Any functional change (those live in F-020–F-024). No new endpoints or data.
- Full rebrand or new design system — this is polish within the existing look.

## Data model changes
- None.

## Affected files
- `src/lib/shared/**` (icons, cards, labels, calendars), and the `src/lib/live/Server*` components that render customer and staff screens. Exact list produced during the audit step.

## API contract additions/changes
- None.

## Permissions / security notes
- No access or data change. Ensure polish does not expose any field that was previously hidden (e.g. amounts without `viewIncome`, staff names/reasons in customer views).
- Accessibility: labels tied to inputs, icon-only controls get accessible names, colour contrast (including the green warranty text and red accents) passes in light and dark.

## Test plan
- Happy: representative screens (book, my-bookings, account, points, staff bookings/reports) reviewed at 360/768/1440px, light and dark — no overflow, clear labels/icons/segmentation.
- Edge: long labels, empty states, no clipping.
- Regression: svelte-check 0 errors, whole `npm test` suite green, Worker build + size budgets pass (icons must not blow the budget).
- Accessibility: keyboard focus visible, icon buttons have names, contrast checks pass.
- E2e: key flows still work after restyle (sign in, book, my bookings, staff review).

## Dependencies / order
- Last. Do after the functional features so polish covers their final markup and does not get re-done.

## Open questions for the owner
- None blocking. (Q-M icon style, Q-N priority screens — both resolved as sensible defaults 2026-11-26; owner may flag specific screens later.)

## Ready checklist (no code until all are ticked and the owner approves)
- [x] Every user step is written out
- [x] Rules, limits and permissions are decided
- [x] Screens and their states are described
- [x] Data and API are designed (none)
- [x] Edge cases and "must not break" are listed
- [x] Acceptance tests are written
- [x] No open questions left
- [x] **Owner approved:** 2026-11-26
