# Server code (`src/routes/api`, `src/lib/server`, `src/workers`, `supabase/`)

Loaded only when working on the API. Screen code is not needed here: read `docs/api-contract.md` instead.

- `docs/api-contract.md` is the promise to the screens. Update it in the same change when an endpoint, field, permission or error changes. Add fields; don't rename or remove them.
- Every endpoint checks who is calling on the server (verified customer owns the record, or staff membership plus the right grant). A hidden button is not access control.
- Read JSON bodies with `readJsonBody` from `src/lib/server/request-body.ts` (size limit) and validate every field. Recalculate prices, capacity and balances on the server.
- Database changes go in a new file in `supabase/migrations/`. Never edit one that has already run. Add a policy assertion in `tests/database/` for new access rules (one allowed actor, one denied actor).
- Keep private evidence, Auth and staff data out of public responses, logs and caches.
- Use Philippine time for bookings and reports.
- Tests: `npm test` (unit), plus the database checks in CI. Add a test for every endpoint or rule you change.
