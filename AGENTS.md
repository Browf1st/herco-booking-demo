# Working on HERCO

HERCO is a SvelteKit Cloudflare Worker app for Supabase-backed customer and staff workflows. The static GitHub Pages demo is retired; references are archived in `docs/archive/demo/`. The current production and staging status is in [the handoff](docs/production-handoff.md).

## Where things are
- `docs/roadmap.md`: progress and what's next. `docs/features/F-xxx-*.md`: one spec per feature. No new feature work until its spec is Ready and approved.
- `docs/api-contract.md`: every `/api` endpoint. It's the only link between screen code and server code.
- Screen code: `src/routes/**` pages and `src/lib/{live,shared}`, with rules in `src/lib/AGENTS.md`. Server code: `src/routes/api`, `src/lib/server`, `src/workers` and `supabase/`, with rules in `src/routes/api/AGENTS.md`.

## Rules
- Keep production business records in Supabase. Check ownership and staff grants in the database and server. Keep private evidence, Auth and staff data out of public responses and caches.
- Treat the original booking, price, promotion, and service snapshots as historical records. Apply new prices to new work and append audited changes to existing work. Use Philippine time for bookings and operating reports.
- Use fictional records in local or staging checks. Keep credentials and private customer data out of Git, logs and test fixtures. Follow the repository account and Git authorization rules provided by the maintainer.
- Run `npm run check`, `npm test` and `npm run build:worker` plus `node scripts/performance-budget.mjs worker` before handing off. See [engineering checks](docs/engineering-checks.md) for database, security, and performance verification.
- Use the HERCO review skill for defect investigations and the security or performance skill when a change affects those areas. Report findings with a file, the affected workflow, and evidence.
- Keep live deployment, cloud resource changes, and external communication within the maintainer's explicit authorization. Applying a migration to a hosted project is a separate release step.
