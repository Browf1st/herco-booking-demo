# F-009: Completion with photos and exact prices
> Documented from existing docs on 2026-11-20 — owner to confirm.

**Status:** Blocked (retention and expanded saved-proof data/API/grant design pending; staff-only viewers confirmed 2026-11-27) · **Milestone:** M2 · **Depends on:** F-003, F-007

> 2026-11-20: the private `herco-completion` bucket exists on the dev Supabase project and was checked: not public, 4 MB limit, JPEG/PNG/WebP only.

## In one sentence
Staff save one to three private finished-product photos while Booked, then complete the job using that saved proof and exact prices; authorized staff can view it on Booked and Completed details.

## User steps (exactly how it works)
1. Authorized staff open the Booked booking, attach finished-product photos and Save proof; they may reopen it later before choosing Complete.
2. Any line still marked "quote" or with a price range must first get an exact price in the service editor.
3. Reuse the saved one to three photos; if none are saved, choose camera/album and Save proof first.
4. Staff confirm; the booking becomes Completed and the action is audited.

## Rules and details
- Needs `completeBooking`. Completion-only staff record the finalized total; a different final charge needs `adjustPrices`.
- Photos: JPEG, PNG or WebP, up to 4 MB each, stored in private bucket `herco-completion`; no browser upload or read access; the server checks permissions.
- Photo count, ownership and exact prices are rechecked inside the completion save; retries cannot repeat completion effects.
- Old completed bookings from before this rule stay valid.
- Viewers: authorized staff/Admin/Owner only, confirmed 2026-11-27. Retention remains open (Q-03); see superseding finished-product proof revision below.

## Screens
- `/complete-booking`: unresolved price warnings, photo picker with previews (1–3), Complete button, upload and validation errors.

## Data
- Private evidence metadata linked to bookings; upload reservations used by cleanup (F-015).

## API
- Photo upload, authorized photo read (short-lived link), complete booking. Paths TBD in api-contract.

## Edge cases and errors
- No photo, a photo from another booking, wrong file type or size → completion refused.
- A quote or range line left → completion refused with the line named.
- Double tap on Complete → completed once.

## Must not break
- Reports' Completed service value (F-011), points (F-010), historical completions.

## Acceptance tests (all must pass)
- [ ] Completion fails with 0 photos or 4 photos, passes with 1–3.
- [ ] Unrelated or invalid photos are refused.
- [ ] Unresolved quote or range blocks completion.
- [ ] Photos cannot be opened without permission (direct URL too).

## Owner-confirmed finished-product proof revision — 2026-11-27

- Owner chose **finished-product photos only** (option B), with photos attachable and saved while the booking is **Booked/confirmed**, before staff press Complete. These are not intake/before-condition photos. Owner chose **authorized staff/Admin/Owner viewers only** (option A); customers cannot read these photos even for their own booking.
- Staff open booking details → **Finished-product proof** → Add photos → choose camera or album → preview → Save proof. Uploading/saving proof alone leaves the booking Booked: it does not finalize price, award points, create completion events or send completion emails. Show progress, per-file errors, retry, empty state and a clear saved indication. Reopening the booking must show saved proof; refresh must not lose it.
- Keep the existing 1–3-photo completion requirement, exact-price checks and 4 MB-per-file JPEG/PNG/WebP limits unless separately revised. A saved proof set can be reused by Complete; the database rechecks booking ownership, accepted file metadata/count, current grants, lifecycle and exact prices in the completion transaction. Completion must not demand another upload of already-valid saved proof or duplicate files/events on retry.
- Booked proof is **linked booking evidence**, not an abandoned upload. Persist booking/object association, uploader, timestamps and lifecycle metadata before completion; ensure cancellation/failure does not silently erase evidence. F-015 includes linked Booked and Completed proof in backup and excludes it from abandoned-upload cleanup. Retention, cancellation retention, and later replacement/deletion rules remain unanswered; no destructive policy is approved.
- Upload/save continues to require completion/photo-upload permission and an eligible Booked booking. Viewing requires verified identity, enabled staff membership, relevant booking/detail page access and authorized evidence-read scope; role labels alone grant nothing. Map exact read scope across Bookings, Reports, History and Customers in the API/database design before this extension is Ready; do not force Customers viewers to receive mutation grants simply to see allowed proof.
- Private herco-completion storage only, separate from public colour swatches. Serve bounded authorized image responses; private/no-store, no public object URLs, no evidence in customer payloads/caches/email/analytics/logs. A shared detail component must receive only fields the server authorizes.
- **Compatibility conflict to resolve before release:** current contract describes optional customer sharing and customer shared-photo reads, and existing completion reads may only see finalized proof. Revise the contract, customer UI and server/database/storage access together so both Booked and Completed staff reads work and customer proof reads (including previously shared links/direct requests) are denied. Preserve original evidence/business records; do not simply hide the customer button. Preserve separately approved non-photo shared-note behavior; do not remove unrelated note features merely to deny photos. No existing access path is declared removed by this spec edit.
- Booked and Completed staff details show the saved gallery through F-026. Completed detail is read-only under current approved scope; post-completion proof additions/replacement/deletion require a separate decided policy. Historical completed bookings without proof remain valid and show an honest no-proof state.
- Before code: backend/database design must specify saved-proof association, read/write grant mapping, API methods/errors, idempotency/concurrent saves and rollback-compatible migration. Use a new migration; never rewrite applied migrations. API contract is updated before builders consume it.
- Acceptance: save 1–3 finished-product photos while Booked, navigate away/reopen, see the same saved proof with status unchanged; Complete reuses it once. Validate wrong booking/type/size, empty or fourth photo, duplicate retries, network failure, stale/revoked access, concurrent save/completion. Direct logged-out/customer/unauthorized staff/API/storage reads fail; approved staff can view permitted Booked/Completed proof. Public swatches remain separate. Linked pre-completion proof survives cleanup and is included in restore verification.
- Scope/viewer decisions are confirmed. Retention and final data/API/grant design remain open; F-009 is not made Ready by this update. No implementation, upload or hosted migration performed.

## Ready checklist (no code until all are ticked and the owner approves)
- [x] Every user step is written out
- [ ] Rules, limits and permissions are decided
- [x] Screens and their states are described
- [ ] Data and API are designed
- [x] Edge cases and "must not break" are listed
- [x] Acceptance tests are written
- [ ] No open questions left
- [ ] **Owner approved:**
