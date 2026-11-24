# F-002: Availability, opening hours, date overrides and slot blocks
> Documented from existing docs on 2026-11-20. Opening-hours section written 2026-11-23 from the owner's answers.

**Status:** Ready (approved 2026-11-23) · **Milestone:** M2 · **Depends on:** F-012

## In one sentence
The admin sets the shop's default opening hours and open weekdays, changes single dates when needed, and customers only see hours the shop can take.

## Owner answers (record)
- 2026-11-21 Q-07: the admin sets the general opening hours (e.g. 9 AM–5 PM); these become the hourly slots for every date. Every slot is bookable unless the admin blocks it. No service durations: a booking holds only its own hour.
- 2026-11-23 Q-07 follow-up, owner's words: "Admin set opening hours and it would be their default. Admin can also modify time per day. For example admin can set 8 up to 8 pm, then that would be the default, then they can modify each day like checklist what to show and what not."
- 2026-11-23 Open days: the admin picks the open weekdays (tick boxes Mon–Sun). Today's Wednesday–Sunday becomes the starting value.
- 2026-11-23 Q-07b: **no limit** on bookings per hour. Any number of customers can book the same open hour; the admin blocks the hour by hand when the shop is too busy.
- 2026-11-23 Shorter hours: existing bookings are kept; the admin is warned and shown the list of future bookings outside the new hours, to move or cancel by hand.
- 2026-11-23 Real hours: 8 AM–8 PM was only an example. The shop's real hours stay 9 AM–5 PM (last slot 4 PM); the owner wants admins to be able to change them.
- 2026-11-23 One date: the admin can both tick/untick single hours (checklist) and set different open/close hours for just that date.

## User steps (exactly how it works)
### Default hours (all dates)
1. Staff with `manageSchedule` open **Manage Availability** in `/admin` and see the **Opening hours** card.
2. They pick **Opens at** (e.g. 8:00 AM) and **Closes at** (e.g. 8:00 PM) from hourly lists, and tick the **open days** (Mon–Sun).
3. A preview shows the slots: "8 AM, 9 AM … 7 PM · 12 slots a day".
4. **Save**. If future bookings fall outside the new hours or on a newly closed weekday, a box says "3 future bookings are outside the new hours" with date, time and reference for each, and buttons **Save anyway** / **Go back**. Saving never changes those bookings.
5. Customers on `/book` see the new hours right away for every date without its own hours.

### One date
1. Staff pick a date in Manage Availability.
2. Choose one: **Use default hours**, **Closed**, or **Own hours for this date** (Opens at / Closes at just for that date, e.g. Dec 24 8 AM–12 PM).
3. Below, a checklist shows every hour of that date. Ticked = customers can book it. Unticking an hour blocks it; ticking it again reopens it (same as today's Block / Unblock).
4. Hours already passed (Philippine time) show **Past slot** and cannot be changed.
5. **Restore default** removes the date's own hours and closed/open choice; manual blocks stay until unticked.

## Rules and details
- **Who:** only staff with the `manageSchedule` action grant may change default hours, open days, date hours or blocks. Checked by the database function, not only the screen. Everyone else gets "You don't have permission to change the schedule."
- **Slots:** hourly, each starting on the hour. Closing time is when the shop closes, so the last slot starts 1 hour before it: 8 AM–8 PM gives 8 AM … 7 PM (12 slots); today's 9 AM–5 PM gives 9 AM … 4 PM (8 slots). Slot length stays 1 hour for now.
- **Limits:** opens 12 AM–11 PM, closes 1 AM–12 midnight, closing after opening, at least 1 slot. Hours cannot run past midnight. At least one open weekday.
- **Starting values:** 9 AM–5 PM, Wednesday–Sunday, so nothing changes for customers until the admin saves new hours.
- **Which hours apply to a date**, in order: (1) the date's own setting (Closed / Own hours / Open with default hours), else (2) open if its weekday is ticked, with the default hours. Then manual blocks remove single hours. Past hours are never bookable.
- **Per-service days stay:** a service's own allowed weekdays (e.g. Powder Coating only Wed, Sat, Sun) still apply on top of the shop's open days.
- **No limit per hour:** many bookings can share one hour. Customers see an hour as **Open** or not shown; they never see how many others booked it. Staff calendars show the count, e.g. "10 AM · 3 booked".
- **Existing bookings are history:** changing hours, open days, date hours or blocks never moves or cancels a booking. Bookings outside the hours stay visible to staff with a label **Outside hours**.
- **Reschedule and new bookings** (customer request, staff approval, staff manual booking, walk-in with a time) must land on an hour that is open for that date at save time. Hours are checked again inside the save.
- **Philippine time:** all dates and hours are Asia/Manila. "Today" and "past" use Philippine time. Changes on today's date only affect hours still ahead.
- **History:** every change to default hours, open days, date hours and blocks is saved in the schedule log (`schedule_events`) with who and when, and shows in the Activity log.
- Public availability shows open/closed only: no names, notes or counts.

## Screens
- **Opening hours card** (Manage Availability): Opens at / Closes at lists, 7 weekday tick boxes, slot preview, Save.
  - States: loading; unchanged (Save disabled); invalid (e.g. "Closing time must be after opening time", "Pick at least one open day"); saving (button busy); warning box with the list of affected bookings; saved ("Opening hours saved"); error ("Couldn't save. Try again."); no permission (card read-only with a note).
- **Date panel:** three choices (Use default / Closed / Own hours), own-hours lists, hour checklist with Past slot labels and "3 booked" counts, Restore default.
  - States: loading; saving per change; error with retry; past date read-only.
- **Staff calendar:** closed dates, per-hour booked counts, **Outside hours** label on affected bookings.
- **`/book`:** shows only the open hours for the chosen date; the line "Appointment hours are 9 AM to 5 PM" uses the real hours of that date (e.g. "Open 8 AM to 8 PM today"). Closed date: "Closed on this date. Please pick another day."
- Works on phones (single column, tick boxes at least 44 px tall) and in light and dark themes.

## Data
- **New table `herco_private.schedule_settings`** (one row): `open_hour` smallint 0–23, `close_hour` smallint 1–24, check `close_hour > open_hour`, `open_weekdays` smallint[] of 0–6 (0 = Sunday, at least one), `updated_at`, `updated_by`. Seeded with 9, 17, {0,3,4,5,6}. RLS on; no access for browsers.
- **`date_overrides`** (reused): keep `is_open`; add nullable `open_hour`, `close_hour` (same checks, both set or both null). `is_open = false` = Closed; `is_open = true` with hours = Own hours; `is_open = true` without hours = open with default hours.
- **`slot_blocks`** (reused, the checklist): widen `visit_hour` check from 9–16 to 0–23.
- **`herco_bookings`**: widen `visit_hour` check from 9–16 to 0–23. Replace the unique index `herco_active_booking_slot` with a normal index on `(visit_date, visit_hour)` where not cancelled (no limit per hour, keeps lookups fast). The retry key `unique (customer_id, request_id)` stays, so double-clicks never make two bookings.
- **New function `herco_private.day_hours(day)`**: returns the bookable start hours for a date from the rules above. `slot_status` and `herco_availability` use it instead of the fixed `generate_series(9, 16)` and the fixed Wednesday–Sunday rule. `slot_status` no longer returns `booked`.
- Every save that sets a visit hour (online booking, reschedule request and approval, staff direct change, manual booking, walk-in with a time) checks `day_hours` and blocks inside the same transaction, holding the existing per-date lock so a block and a booking racing for the same hour are decided one at a time.
- Settings and date changes use the same per-date lock and write a `schedule_events` row.
- New migration only; old migrations are not edited. Applying it to hosted Supabase is a separate step with the owner's OK.

## API (to add to `docs/api-contract.md`)
- `GET /api/staff/schedule-settings` — staff with `manageSchedule` or calendar access. Returns `{ openHour, closeHour, openWeekdays: number[] }`.
- `PUT /api/staff/schedule-settings` — `manageSchedule` only, same-origin. Input `{ openHour 0–23, closeHour 1–24, openWeekdays 1–7 unique 0–6, confirmOutside: boolean }`. If future bookings fall outside and `confirmOutside` is false: `409 { code: "bookings_outside_hours", bookings: [{ reference, date, hour }] }` (no names). Success `200` with the saved settings and `outsideCount`. Errors `400`, `401`, `403`, `503`.
- `POST /api/staff/bookings` gains actions: `set_date_hours` (`date`, `openHour`, `closeHour`) and the existing `open_date`, `close_date`, `restore_date`, `block_slot`, `unblock_slot` (hour 0–23). `restore_date` also clears own hours. `set_date_hours` returns the same `409 bookings_outside_hours` check with `confirmOutside`.
- `GET /api/availability`: same shape; each date also returns `openHour` and `closeHour` (or `closed: true`); only bookable hours are listed with status `open`. No `booked` status any more.
- All `hour` inputs change from "integer 9–16" to "integer 0–23", and the server checks the real hours of that date.

## Edge cases and errors
- Admin shortens default hours; Dec 24 has own hours 7 AM–9 PM → Dec 24 keeps its own hours.
- Admin unticks Wednesday; one Wednesday has an Open override → that date stays open.
- Weekday closed but a date is set Open → uses the default hours.
- A block exists at 7 PM, then hours shrink to 5 PM → the block stays saved but has no effect; it comes back if hours grow again.
- Bookings outside new hours → kept, labelled **Outside hours**, listed in the warning; customer is not emailed.
- Customer has the booking page open while the admin closes the hour → the booking save is refused: "That time is no longer available. Please pick another." (409).
- Reschedule approval into an hour that is now closed, blocked or outside hours → rejected with the same message.
- Opening equals or is after closing, no open day, hour 24 for opening, text instead of number → `400` with a clear message.
- Changing hours for a past date → refused.
- Two admins save different hours at the same time → the later save wins; both are in the log.
- Same customer books the same hour twice for two bikes → allowed (no limit); the retry key still stops accidental double submits.
- Philippine midnight: at 11:30 PM a 12 AM slot for tomorrow is future, not past.

## Must not break
- Existing appointments on closed dates or outside hours stay unchanged (F-001, F-006, F-007).
- Customer booking (F-001), change requests (F-006), staff queue and calendar (F-007), manual and walk-in bookings (F-008), reminders and emails (F-014).
- Per-service allowed weekdays.
- Original booking, price and service snapshots.
- Until the admin saves new hours, customers see exactly today's 9 AM–4 PM slots, Wednesday–Sunday.
- Planned change, not a break: tests that expect a second booking in the same hour to fail ("slot taken") will be updated, because the owner chose no limit.

## Acceptance tests (all must pass)
- [ ] With starting values, `/book` shows 9 AM–4 PM on Wed–Sun and nothing on Mon/Tue (same as today).
- [ ] Admin saves 8 AM–8 PM → every default date shows 8 AM … 7 PM (12 slots); a booking at 7 PM succeeds.
- [ ] Admin unticks Wednesday → Wednesdays close; a Wednesday with an Open override stays open.
- [ ] Dec 24 own hours 8 AM–12 PM → only 8–11 AM shown that day; other days unchanged.
- [ ] Unticking 12 PM on a date hides it; ticking it again shows it.
- [ ] Shortening hours with a future 7 PM booking shows the warning with that booking; Save anyway keeps the booking and labels it Outside hours.
- [ ] Booking, reschedule request, staff approval, manual and walk-in saves at an hour outside the date's hours are refused by the database (tested by calling the function directly).
- [ ] Three customers can book the same open hour; staff calendar shows "3 booked"; customers see only "Open".
- [ ] Racing block and booking never leave a booking in a blocked hour.
- [ ] Past hours (Philippine time) show Past slot and cannot be changed.
- [ ] Staff without `manageSchedule` are refused by the server for every change; customers and signed-out users cannot read or change settings.
- [ ] Invalid input (close ≤ open, no weekdays, hour 25, text) → 400.
- [ ] Closing a date keeps its existing appointments. Unblock/untick only affects manual blocks.
- [ ] Every change appears in the Activity log with who and when.

## Ready checklist (no code until all are ticked and the owner approves)
- [x] Every user step is written out
- [x] Rules, limits and permissions are decided
- [x] Screens and their states are described
- [x] Data and API are designed
- [x] Edge cases and "must not break" are listed
- [x] Acceptance tests are written
- [x] No open questions left
- [x] **Owner approved:** 2026-11-23, in chat ("Yes, approve")
