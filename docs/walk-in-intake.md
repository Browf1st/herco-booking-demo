# Configure walk-in intake

The Worker app supports same-day walk-in booking and adding intake to an existing scheduled booking. Both depend on a project administrator activating an approved form. The first supported signature method is a typed full name with an affirmative acknowledgement from the verified account. Use that method after the shop approves it and the exact form text.

To configure a form, have an authorized Supabase project administrator add an approved row to `herco_private.walk_in_forms` in the intended environment with:

- A unique `version` and the final approved `title` and `body`.
- `signature_method` set to `typed_name`.
- The approving account's verified user UUID in `approved_by` and approval timestamp in `approved_at`.

Retire the previous active row and activate the approved new version in one transaction. A retired version cannot accept new signatures. Previously signed intake remains linked to the original wording. Make text changes by creating a new version. Configure retention before processing real intakes.

## Same-day walk-in

1. At the shop, the customer opens `/walk-in`, signs into a verified account, selects services available that day, and signs the active intake form.
2. HERCO saves the signed form and the walk-in together. It uses the current Philippine date and leaves the appointment hour empty. No calendar slot is held.
3. The booking appears under **Walk-ins** on the staff booking day. The shop confirms it before service. Customers can see the status and signing event in My Bookings and should contact the shop for changes. Staff can cancel it that day if authorized.

## Intake for an existing appointment

1. The shop opens a scheduled booking at `/walk-in-intake?booking=<booking-reference>`. The staff member must verify with an authenticator and hold both **Bookings** and **Create manual bookings** permissions.
2. Staff select **Open intake for customer** and give the link to the booking owner through the shop's approved channel.
3. The customer signs into the account linked to the booking, reviews the versioned form, checks the acknowledgement and types the full name shown on the booking. Staff can see that the intake was signed.

Intake requests and signatures produce separate booking events. The signature, approver, request actor and immutable form remain in private database tables. A link alone does not grant access. Guest intake requires a separate approved identity workflow.
