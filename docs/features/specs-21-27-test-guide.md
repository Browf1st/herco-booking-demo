# How to test specs F-021 to F-026

This guide is written for you (the owner). It has two parts:
- **Part A – Set up (you run these once):** turn on the new features on your hosted Supabase dev project.
- **Part B – Click-through checklist:** what to try in the app and what you should see.

Everything the team built is **files only** — nothing has been applied to your hosted Supabase and nothing has been committed to Git. Part A is the owner-authorised release step. **Your Supabase is on the free plan, so there is no automatic backup. One migration (step A2) permanently deletes an old table.** Read A0 first.

---

## Part A — Set up (owner-authorised, do in order)

### A0. Before you start
- These steps change your **hosted dev** Supabase project (`zrwsyezqpizuiiebyssb`). Do them when you're ready to test, not before.
- The free plan has **no backup**. Step A2 drops the old `coating_price_rules` table. The migration first copies every old row into a private `coating_price_rules_archive` table, so nothing is truly lost, but the drop itself can't be undone on the free plan.
- Apply the migrations **in the exact order below**. Each is a file in `supabase/migrations/`. Open the file, copy all of it, paste into the Supabase **SQL Editor**, and run it. Run each one **once**.

### A1–A6. Apply the six migrations (in this order)
Open each file, paste its whole contents into the Supabase SQL Editor, and run it:

1. `supabase/migrations/202611260001_powder_pricing_model.sql` — the new powder pricing model + staff Pricing tab data.
2. `supabase/migrations/202611260002_retire_coating_price_rules.sql` — **archives then drops** the old pricing table.
3. `supabase/migrations/202611260003_powder_booking_options.sql` — lets the new booking screen's choices be saved; removes the Raider/Sniper restriction.
4. `supabase/migrations/202611260004_ceramic_exceptions.sql` — per-bike ceramic prices.
5. `supabase/migrations/202611260005_customer_booking_history.sql` — the customer change log.
6. `supabase/migrations/202611260006_inclusive_closing_slot.sql` — makes the 5 PM slot bookable.

Each migration ends by refreshing the API cache automatically. After running all six, in the SQL Editor run this to confirm they recorded:
```sql
select version from supabase_migrations.schema_migrations order by version desc limit 8;
```
You should see `202611260006` down to `202611260001` near the top.

### A7. Create the public photo bucket
The colour swatches need a **public** storage bucket, kept separate from your private completion-photo bucket.
1. In Supabase → **Storage** → **New bucket**.
2. Name it exactly `herco-swatches`.
3. Tick **Public bucket**.
4. Set the file size limit to **4 MB** and allowed types to `image/jpeg, image/png, image/webp`.
5. Create it.

### A8. (Optional, later) Seed the colour photos
The booking screen works without photos (each colour shows a labelled swatch). To add your real colour photos from the download folder, that's a separate seeding step — tell the team when the bucket in A7 exists and they'll prepare and upload the converted web photos. Until then, colours show as labelled swatches, which is fine for testing.

### A9. Run the app
Start the local dev app pointed at the hosted dev project the way you normally do. Sign in as a staff account (for the Pricing and staff screens) and as a customer account (for booking and My Bookings).

---

## Part B — What to try (click-through checklist)

### F-021 — Staff Pricing tab (sign in as staff with pricing permission)
- [ ] Open the **Pricing** tab. You should see new sections: a **base price grid** (4 colour types × 4 sizes), a **colour manager**, **bike tiers**, and **price exceptions**.
- [ ] The base grid is pre-filled with the agreed prices. The **Custom** row and the **Not sure** column show **"Quote"** and can't be edited.
- [ ] Add a colour (name + type), **Save**, then add a photo to it. It should preview.
- [ ] Toggle a colour **Off** — it should still save; it just won't show to customers.
- [ ] Add a **price exception** (a bike + a colour → a special price). Save.

### F-022 — Powder booking (sign in as a verified customer)
- [ ] Start a powder booking. Pick a wheel size: **10–14 in, 15–17 in, Big bike, Not sure**.
- [ ] Any bike can now pick **15–17 in** (no "Raider/Sniper only" block).
- [ ] Pick a category → see colours as **photo swatches** (or labelled swatches) → pick one → an **instant price** appears.
- [ ] Pick **Custom** → no price, a "the shop will quote this" message, reference photos, and an **optional description box**. Submitting books it as a quote.
- [ ] The price you set as an exception in F-021 should show for that exact bike + colour.

### F-023 — Ceramic booking (customer)
- [ ] The ceramic section looks modern. Add-ons are **tappable cards you can tick several of** (not plain text).
- [ ] "2–5 years with proper care" shows **once, in green**. The turnover line reads "◷ 2–3 hours turnover · wait at shop or pick up later".
- [ ] (Staff) In the Pricing tab exceptions editor, choose service **Ceramic** and set a per-bike ceramic price; it should apply on the booking screen.

### F-024 — My Bookings (customer)
- [ ] Each booking card has **one red Actions menu** (not three buttons). The menu shows **Reschedule / Cancel / Withdraw request / View details** only where allowed.
- [ ] Tapping a card opens the full detail popup with a **change log**: each price change shows **from → to pesos, "You" or "Shop", and the time** — **no staff reasons or names**.
- [ ] The menu closes on tap-away, Esc, and the phone Back button.

### F-026 — Staff Bookings (staff)
- [ ] The **"All slots"** filter is tidy and the arrow is aligned.
- [ ] Each time slot **lists every booking**, each tagged **Ceramic / Powder / Ceramic + Powder**.
- [ ] Tap a booking → detail popup with a **Status badge + reference** top-right, and **Edit price / Edit service** top-right (only if you have the grants).
- [ ] **Edit price** shows **two boxes**: current (read-only) and proposed new price.
- [ ] **Edit service** is pre-filled and shows a **summary of the change** before you confirm.
- [ ] The old global "View same-name bookings" button is gone; a customer's past visits appear only inside that customer's record.

### 5 PM slot (staff + customer)
- [ ] With hours 9 AM–5 PM, the booking calendar and staff day view now offer a **5 PM** slot (before, the last was 4 PM). A booking at 5 PM is accepted; 6 PM is still refused.

---

## Still waiting on your decision (not blocking the test)
1. **"Change-from-matte" exceptions:** plain per-bike + colour exceptions work. The conditional "only when changing from matte" needs a new customer "current finish" field the specs don't define — want it, or leave it?
2. **MFA on pricing:** changing prices needs a staff password login + the pricing grant (not an authenticator code). Is that the bar you want?
3. **Exceptions vs "Custom is always a quote":** a per-bike exception can set a fixed price even for a custom colour. Keep that staff override, or lock custom to quote always?

## Not done yet
- Colour-photo seeding (A8) — after the bucket exists.
- A final QA + misuse review pass is being run before you rely on this.
