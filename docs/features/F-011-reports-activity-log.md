# F-011: Reports and activity log
> Documented from existing docs on 2026-11-20 — owner to confirm.

**Status:** Needs answers · **Milestone:** M2 · **Depends on:** F-009, F-012

## In one sentence
The Owner and permitted staff see booking counts, service value and promotion totals, and a log of who did what, so the business can be tracked and checked.

## User steps (exactly how it works)
1. Owner signs in and lands on **Reports** (`/reports`).
2. Picks a date range (Philippine time) and sees booking counts, **Completed service value**, average service value, promo totals and net corrections.
   - Reports layout (owner-approved 2026-11-23): period chips in one row, other filters behind "Filters (n)" and applied instantly, completed income first and large, then the other numbers, one expandable "How these numbers are counted" line, a table on desktop and cards on phones, details in a popup sheet.
   - Booking Reports redesign (owner-approved 2026-11-23, from the owner's desktop and mobile mockups): see "Booking Reports layout v2" below. It replaces the 2026-11-23 layout above where they differ.
3. Opens **Activity log** (`/activity-log`): module filter, search, labeled entries, date range up to 31 days, 10 entries per page (owner 2026-11-23; the server returns at most the latest 100 for the dates).

## Rules and details
- Page grants Reports and Activity log; `viewIncome` controls money figures.
- Staff with Reports access alone do not receive final charges in rows, activity or exports.
- "Completed service value" = sum of recorded final service prices for completed work. It is not money collected.
- Post-completion corrections change reports by the difference; a separate net-corrections figure is shown.
- Audit events are saved with the verified actor in the same save as the change.
- Collected revenue: only if an approved source and adjustment rules are supplied. TBD — ask owner (Q-04).
- Report exports and their limits: TBD — ask owner.

## Booking Reports layout v2 (owner-approved 2026-11-23)
Owner's words: follow the mockup's layout "from Booking Reports down", not its top menu; remove Export Report; "+ New Walk-in Booking" becomes **Book** with a dropdown for Walk-in or Online; the side inspector becomes a **More details** popup so the table gets the full width; mobile version and a properly blended dark mode. Each piece of data gets its own visual treatment (chips, pills, avatars), not plain text.
- **Only real numbers** (owner 2026-11-23): no workshop capacity, bay, "paid in full"/"verified ledger", % change, average ticket or pending pipeline.
- **Header:** "BOOKING REPORTS" title, small "Workshop view" chip, subtitle; right side a red **Book** button with a menu: **Walk-in** (opens the walk-in form) and **Online** (opens the manual booking for a customer account). Shown only to staff allowed to create those bookings.
- **Filter card:** period pills (All dates, Today, Last 7 days, This month, Custom range; active pill red), divider, **Filters (n)** button, **Reset filters** link on the right. On phones the pills scroll sideways and Filters sits by the title.
- **Income card** (only with `viewIncome`): dark green-to-slate card, "TOTAL INCOME FROM COMPLETED SERVICES", the amount large, "from N completed services (refs)". Hidden without `viewIncome`.
- **5 count cards:** Bookings in period; Completed services (green); Pending and booked (amber, "x pending • y booked"); Walk-in bookings (refs when few); Cancelled bookings (rose, refs when few). On phones these fold into the income card as a 3-up grid plus 2 small rows, as in the mobile mockup.
- **"How these numbers are counted"** link under the cards (expands the existing notes).
- **Booking records table** (full width on desktop): header "BOOKING RECORDS", subtitle, "N records • Newest first" chip, sort menu (Date newest, Price high–low, Status). Columns: Customer & vehicle (initial avatar, name, reference chip, bike), Date & time (Walk-in shown as a purple dot label), Services (count chip), Status pill with icon (Pending amber, Booked/Confirmed rose, Completed green, Cancelled muted with the bike struck through), Price, Action (**Details** button). The row whose popup is open is highlighted with a red left edge. Pager footer "Showing 1 to 9 of 9 entries".
- **Price column** (only with `viewIncome`): Completed → final price (bold green); Pending/Booked → the booking's original estimate (normal text); Cancelled or unknown → "—".
- **Phones:** booking cards instead of the table: name + reference chip, bike, status pill, date · time, services and price, a **Details** button and a Call icon.
- **More details popup** (centred dialog on desktop, bottom sheet on phones, Esc/backdrop/Close to dismiss, focus kept inside): title "More details", "Details for {name}"; status pill + reference; **Services ordered** with each item's price and "Estimated service value" bar (money only with `viewIncome`); **Customer & motorcycle** with bike, customer name, phone with **Call** and email with **Email**; four tiles: Visit scheduled, Booked on, Approved, Completed ("Not recorded" when missing); action buttons the staff member is allowed to use (Approve booking, Reschedule, Cancel booking), reusing the existing actions.
- **Dark mode:** same layout using the site's theme colours; cards, pills and the income card readable in both themes.
- **States:** loading, empty ("No bookings found" + Reset filters), error with Try again, no income permission.
- Both builds (demo and Worker) get the same layout. Not included: the mockup's top menu, global search, clock, bell, profile, footer and bottom tab bar (the app already has its own).

### Revisions (owner 2026-11-24)
- Remove the "Workshop view" chip, the "How these numbers are counted" link, the "from N completed services (refs)" line, and every small description under the count cards (refs, "4 pending • 2 booked", tag chips). Cards show only the label and the number.
- Remove the "N records • Newest first" chip. Add a **search box** in the table header (name, reference, bike, phone, email), applied as you type.
- Sort menu: **Date (newest)**, **Date (oldest)**, **Price (high to low)**, **Price (low to high)**, **Status**. Price sorts only with `viewIncome`, sorted on the server across all records.
- Period pills, Filters and Reset filters must fit phones: one row that scrolls sideways, with Filters and Reset on their own row below; nothing cut off or squeezed at 360px.
- Total income counts only completed services. The popup and the Price column say **Price**, never "Estimated service value". Staff price changes and added services: see F-007 "Price changes and added services after inspection".
- Activity log: the Apply dates button uses the site's red button style.
- Second batch (owner 2026-11-24): Reports are only reports. Details in the Reports tab is **read-only**: no Approve, Reschedule, Cancel, price edit or Add service (the Changes history may stay, read-only). All booking actions move to the Bookings tab, which uses the same More details popup design (see F-007).

## Screens
- `/reports`: date selector, totals, empty range state.
- `/activity-log`: filter, search, date range, paginated entries.

## Data
- Booking events and audit tables; aggregate report functions.

## API
- Report and activity log reads. Paths TBD in api-contract.

## Edge cases and errors
- Range over 31 days on activity log → refused with a message.
- Bookings near midnight → counted by Manila date.

## Must not break
- Historical completed amounts and promotion snapshots (F-004).

## Acceptance tests (all must pass)
- [ ] Totals reconcile with completed bookings in staging.
- [ ] Reports-only staff never receive final charges (direct API too).
- [ ] Non-staff cannot read reports (verified on hosted project).
- [ ] Every staff action appears in the log with actor and time.

## Ready checklist (no code until all are ticked and the owner approves)
- [x] Every user step is written out
- [ ] Rules, limits and permissions are decided
- [ ] Screens and their states are described
- [ ] Data and API are designed
- [ ] Edge cases and "must not break" are listed
- [x] Acceptance tests are written
- [ ] No open questions left
- [ ] **Owner approved:**
