---
name: herco-security
description: Defensive OWASP and ASVS review of HERCO Auth, Supabase policies, APIs, private data, uploads, secrets, and release controls.
---

# herco-security

Read `docs/engineering-checks.md` and the relevant parts of `docs/production-handoff.md` from the checkout root. Trace each changed boundary from the requesting identity through SvelteKit and Supabase to the record or operation. Check current grants, MFA, RLS, cache behavior, and failure handling independently. Run scoped local checks with fictional identities and report confirmed fixes, remaining risks, and staging checks.
