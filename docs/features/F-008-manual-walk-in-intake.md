# F-008: Manual booking, walk-in and intake form
> Documented from existing docs on 2026-11-20 — owner to confirm.

**Status:** Blocked (approved form text and signature method) · **Milestone:** M2 · **Depends on:** F-005, F-012

## In one sentence
Staff can book for scheduled customers, walk-in customers can book same-day at the shop, and customers sign a versioned intake form before work starts.

## User steps (exactly how it works)
Manual scheduled booking:
1. Staff open **Booking → Manual booking → Online** (`/manual-booking`). The current screen requires a verified customer account. The approved change will also let staff book for a customer who has no HERCO account.

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
- Owner decision 2026-11-25 (Q-10): Staff with booking permission can create manual bookings for customers without a HERCO account. In staff records, group bookings under the same recorded customer name. Match names regardless of capitalization or leading, trailing, or repeated spaces. Keep different spellings separate and preserve the original spelling on each booking. Name grouping is for staff browsing only. It does not link accounts, merge customer records, or grant access in My Bookings.
- Form and evidence retention and visibility: TBD — ask owner (Q-03).

## Screens
- `/manual-booking`, `/walk-in`, `/walk-in-intake`; staff Walk-ins list; customer sees signing event in My Bookings.

### Booking groups for staff

Hosted setup reminder (owner 2026-11-26): migration `202611250002_staff_guest_booking.sql` still needs installation/cache preflight and verification on the connected Supabase project. The API currently cannot find the grouping function (`PGRST202`). Follow the unchecked [Supabase setup checklist in F-026](F-026-staff-booking-revamp.md#required-supabase-setup-reminder--pending); merging application code does not install this database function. Clickable full read-only visit details in Customers are planned in F-026, not implemented here.

- **Customers:** Open a name group to see its booking count and bookings, newest visit first.
- **Booking History:** Keep the date-ordered list. Add a way to open the full same-name booking group from a booking.
- Show each booking’s reference, visit date, and status in the grouped list. Label the group by recorded name because different people may share one name. Apply each screen’s existing staff permissions.

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
- [ ] An admin or staff member with booking permissions can create a manual booking for a customer without a HERCO account.
- [ ] Staff can open the same-name booking group from Customers and Booking History. Capitalization and extra spaces match. Different spellings stay separate, and name grouping grants no access in My Bookings.
- [ ] Staff without the grants are refused.

### Approved implementation for guest scheduled bookings

- Add **Book without an account** beside the existing verified-account lookup in Manual booking → Online. Require the customer name as the only contact field. Mobile is optional. Keep the existing motorcycle, service and appointment slot requirements. Guest bookings have no account or email recipient. The owner approved the scope on 2026-11-25. Keep the existing walk-in signature flow and verified-account booking flow.
- Store guest bookings in the regular booking table with no account owner. Allow that only for bookings created by authorized staff through the guest flow. Enforce staff permission, scheduling capacity, price checks and duplicate-submit protection in the database. Check staff editing, rescheduling and completion with no owner.
- Add staff-only name-group lookups for Customers and Booking History. Use the same grouping rules in both. Keep existing account records, staff permissions and customer booking visibility. Include the total booking count and let staff page through all matching bookings.
- Verify that staff without booking permission cannot create guests, customers cannot access guest bookings, retries save once, competing bookings respect slot limits, and verified-account bookings and signed walk-ins still work.

### Local test scenario for guest manual bookings

Use a local test database and open **Manual booking → Online** as staff with booking permission. Choose any available service and a different available slot for each booking. Use these fictional records:

| Customer name as entered | Mobile | Motorcycle | Expected group |
| --- | --- | --- | --- |
| Test Mara Villanueva | (blank) | Test Honda Click | Test Mara Villanueva |
| test mara  villanueva | (blank) | Test Yamaha Mio | Test Mara Villanueva |
| Test Mara Villanuevas | (blank) | Test Honda Beat | Test Mara Villanuevas |

1. Save each booking using the guest option and note its booking reference.
2. In **Customers**, search for Test Mara Villanueva. Open the exact matching name group. It should show two distinct booking references, newest visit first. The differently spelled name should be a separate group.
3. In **Booking History**, find either of the first two references and open its name group. It should show the same two bookings. Closing it should return you to the same date filters and page.
4. Verify the original name text on each booking and confirm that signing in to a customer account does not expose the guest bookings.

## Ready checklist (no code until all are ticked and the owner approves)
- [x] Every user step is written out
- [ ] Rules, limits and permissions are decided
- [ ] Screens and their states are described
- [ ] Data and API are designed
- [x] Edge cases and "must not break" are listed
- [x] Acceptance tests are written
- [ ] No open questions left
- [ ] **Owner approved:**
