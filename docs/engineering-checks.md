# HERCO engineering checks

The [repository guide](../AGENTS.md) applies to both assistants. Codex loads the entry points in `.agents/skills`; Claude Code has equivalents in `.claude/skills` and reviewer roles in `.claude/agents`. Keep the workflow here so the assistants use the same checks.

## Review and fault tracing

1. Identify the failing workflow, the expected behavior, the build and environment, and the smallest relevant change. Read staged, unstaged, and relevant new files. Trace UI state through the route, provider call or database transaction as needed.
2. For a booking failure, correlate a non-sensitive request or booking reference across the Worker, booking activity, database and, when relevant, the outbox. Keep authentication material, signed links, customer details and raw payloads out of the report.
3. For a database or Auth change, verify an allowed actor and at least one denied actor. Use isolated PostgreSQL, fictional identities and concurrent requests when the workflow has a race. A UI denial alone is insufficient evidence.
4. Record the change, the smallest test that covers it, and the observed result. Review findings should rank concrete issues by impact and name the file, condition and correction. List missing evidence separately.

## OWASP verification

Use the [OWASP Top 10:2025](https://top10.owasp.org/) to identify risks and [ASVS 5.0](https://asvs.owasp.org/) to select verification requirements for the affected workflow. This is a working checklist for HERCO.

| Risk area | Verify in HERCO |
| --- | --- |
| A01 Access control | A verified customer can only read or change their own bookings and contact details. Staff operations require verified email, an enabled membership, and the relevant grants. Password sign-in is sufficient; MFA is not required by the approved policy. Test the route and database RPC independently, including revocation. |
| A02 Configuration | Verify CSP, framing protection, private caching, provider callback allowlists, CORS/origin behavior, and separation of demo and Worker environments. Check headers on both rendered and prerendered responses. |
| A03 Software supply chain | Install with the lockfile in CI, audit runtime and development dependencies, and review dependency changes before release. Pin application and Pages workflow actions to verified commits. |
| A04 Cryptography | Use HTTPS, secure session cookies, private Storage and encrypted backups. Review secret placement and ensure production credentials differ from staging credentials. |
| A05 Injection | Validate product data, contact fields, upload type and size, and JSON body size. Bind SQL parameters and verify escaping in CSV, logging, email and other downstream consumers. |
| A06 Insecure design | Recalculate quote totals, capacity and balances on the server. Check booking races, stale estimates, replay and concurrent staff edits. |
| A07 Authentication | Verify sign-in, confirmation, reset, sign-out, OAuth callback and password-based staff access flows. Confirm abuse limits on public account and booking routes in staging. |
| A08 Integrity | Keep original service and price snapshots intact. Deliver email from the transactional outbox. Verify schema migration and recovery behavior with approved fixtures. |
| A09 Logging and alerts | Verify staff activity, email failures, backup failures and external uptime alerts. Use redacted summaries and approved recipients. |
| A10 Exceptional conditions | Test invalid, oversized, stale, rate-limited and unavailable responses. Confirm that failure leaves booking state consistent and shows an actionable message. |

## Performance verification

1. Build the intended target and run its bundle budget check. Compare compressed assets against the recorded baseline from the same target and comparable tooling.
2. Measure booking, My Bookings, staff queue and any changed workflow in a cold mobile run and a repeat run. Record the build, device or emulation, network, and data volume. Check loading states and preserve old results when supplanting a baseline.
3. Inspect route JavaScript, media bytes, long tasks, request waterfalls, and query plans as relevant. Reduce shipped code or repeated work first. Cache only public data where stale results are acceptable. Booking submissions still validate current prices and capacity.
4. Bundle checks measure shipped bytes. Field performance, worker latency and database efficiency require staged or production measurements.

## Commands

```text
npm ci
npm run check
npm test
npm run build
node scripts/performance-budget.mjs demo
npm run build:worker
node scripts/performance-budget.mjs worker
npm audit --audit-level=high
```

The [Engineering checks workflow](../.github/workflows/engineering-checks.yml) applies every migration to a fresh PostgreSQL service and runs [database policy assertions](../tests/database/security.sql). The fixture models the required Supabase roles and Storage tables. Verify the hosted Auth and Storage behavior separately before release. Set `BASE_PATH` to the demo repository path when reproducing GitHub Pages locally.

### Controls that still need staging evidence

- Verify the actual private `herco-completion` bucket, file limit, content types and direct access denial. Verify the served Worker headers. GitHub Pages supplies its own HTTP headers and HERCO sets a CSP meta policy in the static demo.
- Confirm Supabase email confirmation, signup and reset abuse limits, and the approved per-account booking limits that can be enforced even for direct Supabase RPC calls.
- Verify that completion-only staff can record the finalized service total and that a different final charge requires the separate price adjustment grant. Check the private completion record and authorized reports.
- Verify provider delivery, alert routing, storage and database recovery, and production-like mobile and load performance. Use fictional data and the isolated staging account.

Use [the production handoff](production-handoff.md), [email runbook](email-worker.md), and [recovery runbook](recovery.md) for provider setup, alert recipients, and release evidence.
