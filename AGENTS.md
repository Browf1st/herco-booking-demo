# Working on HERCO

HERCO has a static GitHub Pages demo and a SvelteKit Cloudflare Worker app. Use the static build for demo checks and the Worker build for Supabase-backed customer and staff workflows. The current production and staging status is in [the handoff](docs/production-handoff.md).

- Keep production business records in Supabase. Check ownership and staff grants in the database and server. Keep private evidence, Auth and staff data out of public responses and caches.
- Treat the original booking, price, promotion, and service snapshots as historical records. Apply new prices to new work and append audited changes to existing work. Use Philippine time for bookings and operating reports.
- Use fictional records in local or staging checks. Keep credentials and private customer data out of Git, logs and test fixtures. Follow the repository account and Git authorization rules provided by the maintainer.
- Run `npm run check` and the applicable build before handing off. Use both builds for shared UI, build config, platform routing, or cross-environment changes. See [engineering checks](docs/engineering-checks.md) for database, security, and performance verification.
- Use the HERCO review skill for defect investigations and the security or performance skill when a change affects those areas. Report findings with a file, the affected workflow, and evidence.
- Keep live deployment, cloud resource changes, and external communication within the maintainer's explicit authorization. Applying a migration to a hosted project is a separate release step.
