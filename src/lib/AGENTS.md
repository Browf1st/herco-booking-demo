# Screen code (`src/lib`)

Loaded only when working in `src/lib`. Screens live in `src/routes/**/+page.svelte`, and use the components here.

| Folder | What goes here | May import |
|---|---|---|
| `live/` | Supabase-backed Worker screens (`Server*` and friends). Talk to the server only through `/api/*` as described in `docs/api-contract.md` | `shared/` |
| `shared/` | Reusable live UI: icons, calendars, catalog, coating and date helpers, workspace navigation | `shared/` only |
| `server/` | Server-only code (Supabase, Brevo, request parsing). Never import it from a component. Rules in `src/routes/api/AGENTS.md` | `server/`, `shared/` |

- Import with `#lib/<folder>/<File>` from routes, and with relative paths inside `src/lib`.
- Put workflow screens in `live/` and reusable UI and pure helpers in `shared/`.
- Every screen needs loading, empty, error and success states, and works at 360px wide.
- Run the Worker build after changing `shared/`.
