# F-008: Manual booking, walk-in and intake form
> Documented from existing docs on 2026-11-20 — owner to confirm.

**Status:** Blocked (approved form text and signature method) · **Milestone:** M2 · **Depends on:** F-005, F-012

## In one sentence
Staff can book for scheduled customers, walk-in customers can book same-day at the shop, and customers sign a versioned intake form before work starts.

## User steps (exactly how it works)
Manual scheduled booking:
1. Staff open **Booking → Manual booking → Online** (`/manual-booking`) and book for a verified customer account.

Same-day walk-in:
1. At the shop the customer opens `/walk-in`, signs into a verified account, picks services available today.
2. Signs the active intake form; booking and signature save together for today, with no hour and no slot held.
3. It appears under **Walk-ins** in the staff day; staff confirm before service and may cancel that day.

Intake for an existing appointment:
1. Staff open `/walk-in-intake?booking=<reference>` and choose **Open intake for customer**.
2. Staff give the link to the booking owner through the shop's approved channel.
3. Customer signs in, reads the form, ticks the acknowledgement and types the full name shown on the booking. Staff see that it was signed.

## Rules and details
- Staff need **Bookings** page and `createBooking` grant. walk-in-intake.md also says staff verify with an authenticator, which conflicts with the password-only policy (Q-19).
- Signature method built: typed full name plus acknowledgement (Q-01). Owner answer 2026-11-21: walk-in customers must sign in to their own HERCO account to sign the form (already how it works: staff start the walk-in, the customer signs from their own account). Typed name plus tick box stays the method unless the owner asks for a drawn signature. Form text, version and approver: TBD — ask owner (Q-02).
- Only one active form version; a retired version cannot be signed; old signatures stay tied to their wording.
- A link alone grants nothing; the signer must be the booking owner. Guest intake needs a separate identity workflow (Q-09).
- Customers without an account: TBD — ask owner (Q-10).
- Form and evidence retention and visibility: TBD — ask owner (Q-03).

## Screens
- `/manual-booking`, `/walk-in`, `/walk-in-intake`; staff Walk-ins list; customer sees signing event in My Bookings.

## Data
- `herco_private.walk_in_forms` (version, title, body, signature_method, approved_by, approved_at); signatures and intake events in private tables.

## API
- Walk-in create, intake open, intake sign endpoints. Paths TBD in api-contract.

## Edge cases and errors
- No active form → walk-in and intake unavailable.
- Typed name doesn't match the booking → refused.
- Different account opens the link → refused.

## Must not break
- Scheduled slots and capacity (walk-ins hold none).

## Acceptance tests (all must pass)
- [ ] Walk-in with signed form appears under Walk-ins without using a slot.
- [ ] Wrong account cannot sign another customer's intake.
- [ ] Retired form version cannot be signed; old signatures still show their text.
- [ ] Staff without the grants are refused.

## Ready checklist (no code until all are ticked and the owner approves)
- [x] Every user step is written out
- [ ] Rules, limits and permissions are decided
- [ ] Screens and their states are described
- [ ] Data and API are designed
- [x] Edge cases and "must not break" are listed
- [x] Acceptance tests are written
- [ ] No open questions left
- [ ] **Owner approved:**
