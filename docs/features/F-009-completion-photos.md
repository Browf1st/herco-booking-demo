# F-009: Completion with photos and exact prices
> Documented from existing docs on 2026-11-20 — owner to confirm.

**Status:** Blocked (photo retention and viewer rules not decided, Q-03) · **Milestone:** M2 · **Depends on:** F-003, F-007

> 2026-11-20: the private `herco-completion` bucket exists on the dev Supabase project and was checked: not public, 4 MB limit, JPEG/PNG/WebP only.

## In one sentence
Staff mark a job complete only after attaching one to three private photos and confirming an exact price for every line, so every finished job has proof and a final amount.

## User steps (exactly how it works)
1. Staff open the booking and choose complete (`/complete-booking`).
2. Any line still marked "quote" or with a price range must first get an exact price in the service editor.
3. Staff take or choose one to three photos (camera or album).
4. Staff confirm; the booking becomes Completed and the action is audited.

## Rules and details
- Needs `completeBooking`. Completion-only staff record the finalized total; a different final charge needs `adjustPrices`.
- Photos: JPEG, PNG or WebP, up to 4 MB each, stored in private bucket `herco-completion`; no browser upload or read access; the server checks permissions.
- Photo count, ownership and exact prices are rechecked inside the completion save; retries cannot repeat completion effects.
- Old completed bookings from before this rule stay valid.
- Retention and who may view photos (customer or staff only): TBD — ask owner (Q-03).

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

## Ready checklist (no code until all are ticked and the owner approves)
- [x] Every user step is written out
- [ ] Rules, limits and permissions are decided
- [x] Screens and their states are described
- [ ] Data and API are designed
- [x] Edge cases and "must not break" are listed
- [x] Acceptance tests are written
- [ ] No open questions left
- [ ] **Owner approved:**
