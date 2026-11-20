# Screen code (`src/lib`)

Loaded only when working in `src/lib`. Screens live in `src/routes/**/+page.svelte` and `DemoPage.svelte`, and use the components here.

| Folder | What goes here | May import |
|---|---|---|
| `demo/` | Static GitHub Pages demo: screens and browser-storage state (`store`, `operations`, `account`, `staffAccess`) | `shared/` |
| `live/` | Supabase-backed Worker screens (`Server*` and friends). Talk to the server only through `/api/*` as described in `docs/api-contract.md` | `shared/` |
| `shared/` | Used by both builds: icons, calendars, catalog, coating and date helpers, workspace navigation | `shared/` only |
| `server/` | Server-only code (Supabase, Brevo, request parsing). Never import it from a component. Rules in `src/routes/api/AGENTS.md` | `server/`, `shared/` |

- Import with `#lib/<folder>/<File>` from routes, and with relative paths inside `src/lib`.
- Put new code in the folder that matches who uses it. If both builds need it, it goes in `shared/`.
- Known exceptions to tidy later (they work, so don't change them without a roadmap item): `shared/AvailabilityCalendar` and `shared/RewardReceipt` read demo state, and `live/ServerPoints` uses the demo reward helper.
- Every screen needs loading, empty, error and success states, and works at 360px wide.
- Run both builds after changing `shared/`.
