# Demo-to-backend UI audit

Status: comparison only; correction implementation paused for maintainer decisions.

Reference: local `codex/demo` at `f7eedfc` (the branch called demo in this conversation). Compared with the current `main` working tree, including uncommitted changes. This is not a claim that remote refs were freshly synchronized. The connected GitHub profile was verified as the repository's personal account; no remote mutation, commit, or push was performed.

## Required direction

The demo is the visual and interaction reference. Connect that presentation to Supabase rather than replacing it with generic forms. Do not bring back browser-local business storage, fictional production records, demo role switches, or simulated social sign-in. Keep confirmed newer requirements: password-only verified staff access, Owner → Reports, Admin/Staff → Bookings, Client → My Bookings, and permission-filtered main navigation. Confirm exceptions below before correcting UI.

## Evidence and coverage

- Enumerated every tracked source difference against the reference and the new UI files in the working tree. Mapped all customer and staff workflows, including dialogs and conditional states; backend files are recorded as implementation differences, not visual regressions.
- Account, Book, My Bookings, and Points `DemoPage.svelte` copies exactly match their reference route bodies. The Admin copy differs only by the later past-slot correction. The reference worktree itself is clean.
- `src/app.css`, configuration, existing design primitives and the original demo library components have no branch differences. Their presence does not establish Worker parity: the Worker renders separate components.
- Inspected demo and authenticated Worker booking screens in the browser. The visual reference ran the preserved demo renderer, including the disclosed later past-slot fix. Other findings below come from rendering, state, API and CSS source comparison; not every conditional state has a screenshot or live backend fixture. Empty database results are not evidence of missing UI.
- No new UI correction was made after the instruction to compare first. Prior role-navigation changes remain in the working tree for review.

## Difference register

Each numbered row is a correction or decision unit. File locations refer to the checkout's `src/` directory.

### Global layout, navigation and shared pages

| ID | Demo reference | Current backend version / difference |
|---|---|---|
| G01 | Same branded logo, display font, colors, skewed buttons, stripes and global cards | Shared primitives remain; replacement pages discard many component-specific layouts, icons, sizes and spacing. This is primarily a component-reuse failure, not a missing theme. |
| G02 | Demo User/Admin/Owner switches | Hidden in Worker correctly; must remain absent in real deployment. |
| G03 | Demo Admin navigation and grouped Owner Reports/Accounts/Activity + More menu | Most recent Worker change uses a flat permission-filtered staff main menu and Account dropdown. This follows the latest role-nav request, but differs from the demo grouping and density. |
| G04 | Booking/Change requests/Booking history section buttons with pending counters | Worker main navigation now has Booking and Change requests, no counters; Booking history has no supported dedicated staff route. Latest instruction removes inner section navigation; placement needs reconciliation. |
| G05 | Customer Book menu offers Online/Walk-in | Worker customer header has a single Book link; walk-in appears inside its booking flow. |
| G06 | Logo links home | Worker staff logo links to their role landing page; staff opening customer-only pages is redirected. New approved role behavior. |
| G07 | Login stays within demo profile flow | Worker now redirects by role after password login, confirmation/recovery and OAuth callback. Approved revision; not present in reference. |
| G08 | Account profile contains its own controls | Worker staff also have Account settings/Sign out in the main account menu; the account page retains a separate sign-out control. |
| G09 | Original footer | Worker adds Privacy preferences link/page. Theme selector remains shared. |
| G10 | Demo component-specific responsive layouts and dialog backdrops | Replacement Worker screens mostly use generic stacked cards; booking/cart, calendar, ranking, inventory table, reports and dialog responsive rules are not reused. |
| G11 | Demo can show synthetic records immediately | Worker loads actual records and shows loading, failure, denied, retry, empty and stale/conflict states. Retain these states; style them consistently rather than copy fixture data. |
| G12 | Home See more dates expands a full calendar inline | Worker navigates to booking instead. Seven-day cards/hero/services/contact/slider remain shared. |
| G13 | Original image delivery | Home powder image and Showcase image gained responsive sources/dimensions. Visual structure remains the same; retain performance improvements. |
| G14 | Home/Showcase Book buttons preselect service/color | Worker booking only consumes suggested date; service/finish query parameters are not honored. Functional parity gap. |
| G15 | Demo feature toggles drive preview visibility | Shared Home/Showcase still consult the demo feature helper. Determine real configuration source rather than relying on browser fixture toggles. |

### Account and real authentication

Reference `routes/account/DemoPage.svelte`; replacement `lib/live/ServerAccount.svelte`, `ServerContactProfile.svelte`, `StaffSecurity.svelte`.

| ID | Demo reference | Current backend version / difference |
|---|---|---|
| A01 | Centered provider-first login panel, Log in/Sign up toggle, provider logos/divider | Direct generic email/password form and secondary mode buttons; original provider panel styling not reused. |
| A02 | Google/Facebook/email choices visible in demo | Real social providers only show when configured. Must not expose simulated or disabled provider buttons as working. |
| A03 | Signup asks Name | Worker signup omits Name and collects editable name/phone later in Booking contact details. |
| A04 | Signed-in profile emphasizes name/provider, readonly email and phone | Worker emphasizes email and uses a separate name/phone card. |
| A05 | Simulated login has no real password/code/recovery screens | Worker adds password, email confirmation and reset/recovery forms. These need demo-consistent styling, not deletion. Full provider verification codes must remain supported. |
| A06 | No real privileged login workflow | Worker role card now labels Owner/Staff; authenticator requirement and Open staff workspace button were removed by explicit later instructions. |
| A07 | Account profile links My Bookings | Worker still shows this customer action for staff even though the new staff shell redirects customer pages. Needs removal/replacement for staff. |

### Online booking and service selection

Reference `routes/book/DemoPage.svelte`, `BookingCatalog`, `VisitPicker`; replacement `ServerBooking`, `AppointmentCoatingFields`, `booking-coating.ts`.

| ID | Demo reference | Current backend version / difference |
|---|---|---|
| B01 | Four numbered progressive panels, desktop 2:1 layout and sticky booking cart | One stacked card with fieldsets and estimate near bottom. |
| B02 | Designed service cards with descriptions and selection states | Generic catalog-service checkbox rows/prices. |
| B03 | Bike tier/model selection groups and tier prices | Free-text bike field; no tier/model card UI. |
| B04 | PCX model-year field and related pricing context | No model-year field or corresponding Worker booking payload. |
| B05 | Ceramic package coverage/stages, durability/turnover copy and optional add-ons | Ceramic finish/Enhance eligibility controls only; full package/add-on selection not reproduced. |
| B06 | Powder wheel categories/ranges, prismatic option, wheel extras, small-parts toggle | Part checkboxes and front/rear diameter selects; richer configurations absent from Worker draft schema. |
| B07 | Preferred powder color/finish input, suggestions and photo gallery | No equivalent selection/gallery in Worker booking options. |
| B08 | Notes for the shop | No corresponding Worker form/payload field. |
| B09 | Booking email is editable | Worker displays signed-in account email; real identity requirement is approved, editable contact email is a separate decision. |
| B10 | Calendar date picker and clock-icon time buttons | Native date/time dropdowns; available dates limited to fetched next 21 days. |
| B11 | Sticky line-item cart, selected service details and estimate | Simplified nonsticky estimate block, with server quotation states. |
| B12 | Review booking modal, Back to edit, Confirm and submit | Main form submits directly, no review dialog. |
| B13 | Success screen recaps bike/year, service, visit and estimate | Worker success emphasizes reference and total/quote warning, without full submitted visit/bike/service recap. |
| B14 | Demo calculates fixture estimates locally | Worker adds debounced server estimates, stale-price review, retry IDs and real availability errors. Preserve backend safeguards when restoring demo presentation. |

### Walk-in and manual booking

| ID | Demo reference | Current backend version / difference |
|---|---|---|
| W01 | Source selector inside shared booking form | Separate `/walk-in` route and schedule/walk-in links. |
| W02 | Manual walk-in includes Customer is at the shop now; can otherwise choose a scheduled visit | Customer Worker walk-in submits for today without selecting a future slot, per later approval. |
| W03 | Optional email/generic demo acknowledgement and typed signature | Verified account required; actual configured form title/body/version, acknowledgement and matching typed name. Approved real-account flow, not a visual copy issue. |
| W04 | Walk-in intake integrated in booking form | Additional `/walk-in-intake` staff-requested signing page, pending/signed states and customer signing link. |
| W05 | Manual booking dropdown offers Online and Walk-in within schedule and carries selected date | Standalone main-nav Manual booking page; scheduled-only page with exact verified-email lookup before form. No equivalent top-right source dropdown. |
| W06 | Manual booking reuses full demo catalog, review, calendar and cart | Worker manual form has generic service checkboxes, dropdown date/time, contact/bike/plate and success card; no full coating configuration/cart/review. |
| W07 | Demo signature is explicitly fictional | Real legal/intake text may be unconfigured. Preserve unavailable states rather than invent approved wording. |

### Customer bookings, edits and requests

Reference `CustomerBooking`, `BookingSummary`, `EditCoating`; replacement `ServerBookingHistory`, `ServerCustomerChangeForm`, `BookingServiceEditor`, `ServerBookingActivity`.

| ID | Demo reference | Current backend version / difference |
|---|---|---|
| C01 | Card heading is booking reference; service/bike/visit overview with icons | Worker heading is bike; reference moved into details and overview uses plainer text. |
| C02 | Compact card, top-right request buttons, inline View details | Both preserve this general arrangement. Neither current reference nor Worker uses a View details dialog. Earlier conversation contains a conflicting dialog answer, later corrected ambiguously. |
| C03 | Booked/approved/completed timestamp columns | Worker details provide submitted time; approval/completion timestamps absent from customer response. |
| C04 | Current/original services, added/removed changes and before→after price/estimate comparisons inside details | Worker links to separate service-history page; generic original/after lists lack the same comparison presentation. |
| C05 | Shop approval/cancellation/completion notes and completion photos in customer details | Worker customer response does not supply these fields/photos. Approval note is currently private on staff screen; requires a visibility decision. |
| C06 | Cancellation/reschedule dialogs with calendar/time-grid picker | Worker inserts inline request form with native selects. |
| C07 | Pending service edit opens rich inline EditCoating | Worker links to separate `/booking-services` generic service checkbox editor. |
| C08 | Rich integrated activity/service summary | Worker loads activity separately and shows bounded lists/request history. |
| C09 | Demo empty state may include example card | Worker true empty state, real pagination, denied/retry states; preserve honest backend behavior. |
| C10 | Demo request state flow | Worker also supports request withdrawal, future-time restrictions and walk-in instructions. Keep newer approved functionality in demo styling. |

### Staff booking schedule, requests and history

Reference `routes/admin/DemoPage.svelte`, `AdminCalendar`, `AdminBooking`, `OperationsAdmin`; replacements `ServerStaffBookings`, `ServerStaffRequests`, standalone task pages.

| ID | Demo reference | Current backend version / difference |
|---|---|---|
| S01 | Booking schedule eyebrow, large date heading, colored availability badge and override status | Generic Staff bookings heading, date input, second date heading and text. |
| S02 | Three colored Pending/Booked/Completed summary tiles | Missing from Worker schedule. |
| S03 | Month calendar left, slots right; month navigation, jump-to-month, Today, status counts and legend | No month calendar/sidebar; native date and previous/next buttons above one stacked slot list. |
| S04 | Time slots heading and counted status-filter dropdown | No counted slot filter control. |
| S05 | Online/walk-in/all source filter | Missing from Worker schedule. Walk-ins are shown separately. |
| S06 | Slim horizontal time/status cards with booking summary | Large generic stacked cards per hour. |
| S07 | Manage availability opens styled modal with date controls and restrictions | Permanently visible card for date controls, block/unblock buttons on each main slot card. |
| S08 | Availability states inside dialog | Worker adds authoritative past-slot states; retains real block/unblock. Preserve later bug fixes when restoring dialog. |
| S09 | Primary action top-right + More actions dropdown + Tap to view more | Worker nests action links/forms under View details; action hierarchy/placement/icons differ. |
| S10 | Confirmation modal with note for customer | Inline private approval-note textarea and Confirm booking. Note visibility differs, not just layout. |
| S11 | Cancellation/reschedule/review dialogs | Worker direct changes use inline form; request queue approves/declines directly on generic cards. |
| S12 | Booking cards show complete summary/service-history/customer context | Worker uses smaller data projection, generic text and separate task-page links. |
| S13 | Completion form lives in booking workflow, camera/album controls, preview/remove and final price | Standalone `/complete-booking` page with file/camera inputs, note/price and saved evidence states. Allowed image types/limits are backend enforced and differ from demo AVIF support. |
| S14 | Service/price edit integrated into richer booking edit | Separate `/booking-services` and `/booking-prices`, generic service selection/exact-price form and audited correction history. Preserve post-completion correction feature. |
| S15 | Change requests have counted section, full booking card and review modal | Separate main route/query view with simpler request/customer/date/reason cards and Approve/Decline buttons; no count badges. |
| S16 | Booking history workspace: five metric filters, name/ref/mobile/bike/plate search, date presets/exact/range, status/source, reset, expandable cards, pagination | No equivalent dedicated Worker staff-history view or navigation route. Not fixed by restoring CSS alone; data/query work required. |

### Customers, points, inventory and management

| ID | Demo reference | Current backend version / difference |
|---|---|---|
| O01 | Customers: live search by name/email/mobile/account ID; expandable profile with booking history and bike/count summary | Submit-search name/full-email directory, View visits button, separate paginated visits panel; less record detail, different expansion layout. |
| O02 | Staff Points: ranked/searchable/sortable fans with name/contact context | Adjust points requires raw Member ID. Staff ranking/search/selection UI missing. |
| O03 | Manage points popup with add/correct modes and points history | Always-inline signed adjustment + required reason form; no member ledger display in this page. |
| O04 | Reward editor popup with reward name, scope and points | Inline add/edit enabled reward form; scope field absent. |
| O05 | Redemption search, status and sort filters; expandable AR cards | Recent redemption cards and approval/claim buttons without those filters/receipt layout. |
| O06 | Customer Points: fan summary, reached/progress/points-remaining reward cards, balance confirmation | Plain balance card, text reward rows and simpler inline confirmation. |
| O07 | Customer Points: Top 10/own rank, sticky desktop leaderboard, points ledger and expandable AR receipts | No ranking/ledger/progress layout or RewardReceipt component; API exposes balance/rewards/receipts only. |
| O08 | Customer Points signed-out two-column welcome and reward preview | Simple sign-in message/button. |
| O09 | Inventory overview metric cards | No equivalent dashboard metrics in Worker. |
| O10 | Search/category/stock-status filters and stock table | Generic item cards without equivalent search/filter/table presentation. |
| O11 | New/Edit inventory dialogs, dropdown category/unit and manage-units/categories popup | Inline form, free-text unit/category; management popup/options UI missing. |
| O12 | Per-item Stock in/Stock out/Edit actions and dedicated quantity popup | Single signed Adjust stock form with mandatory reason. |
| O13 | Styled stock history with item filter/pagination | Recent activity disclosure without equivalent controls. |
| O14 | Grouped inventory details (supplier/location/unit cost/billing rate/capacity etc.) | Underlying advanced fields now present, but flat inline controls and generic item summary. |
| O15 | No matching inventory export control in reference | Worker adds stock/movement CSV and date controls; keep and integrate with demo design. |
| O16 | Pricing: ceramic tier grid, addon ranges/listed-addon prices and premium gloss rule; simple booking promo | Generic service catalog CRUD, quote/range/day controls, enabled state; separate coating-rule editor and code/label/enabled promo form. Major information-architecture/data-model difference. |
| O17 | Reports: date presets/reset, search/status/source filters, summary presentation and paginated booking-record table with histories | From/Through form and aggregate definition list only. No report-record table/search/status/source/presets/reset. |
| O18 | Activity: module dropdown/search, labeled module, human-readable actor/target/detail | Date-range form, up-to-100 generic cards, raw actor/reference IDs, no module/search controls or equivalent detail. |
| O19 | Staff access: Add account/Edit modal, name/email, active dropdown, separate pages/actions sections, Select all/Clear all, Preview access | Inline verified-existing-email grant form, no name field, enabled checkbox, actions nested by page, no bulk controls or preview; adds Restricted Admin and revision conflict states. |
| O20 | Simulated preview can select staff identity without authentication | Must not copy impersonation behavior. A read-only permission preview could restore the design safely; requires scope confirmation. |

### Additional real-backend differences to retain

Privacy preferences/analytics consent, configured provider flags, real password/recovery forms, customer contact persistence, quote corrections, intake signing links, CSV exports, private photo evidence, server errors, retries, pagination, conflict handling and authoritative timestamps need demo-consistent presentation. They have no exact matching screen in the reference. Role grants must stay on server/database; copying the demo's client-only role logic would remove required protection.

## Questions before corrections

1. Restore demo presentation for all register items by default, with the newer approved role redirects/main-menu/password-only policy kept? Confirm how to group Booking/Change requests/Booking history in the main header without inner tabs, and whether Owner More grouping should remain.
2. Keep the demo's modal/inline interactions exactly (availability, booking review, requests, completion, points, inventory, access editor), including inline View details, or make specific exceptions? Resolve the earlier details-dialog answer explicitly.
3. Decide true behavior/data conflicts: customer-visible approval notes and completion photos; richer demo coating/addon/color/model-year/notes fields; readable booking/AR references; live provider buttons only; mandatory verified-account walk-ins; safe permission preview. Restoring these features may need schema/API changes, not only component markup.

## Correction acceptance checklist (not yet implemented)

- [ ] Confirm questions and exceptions; record each against IDs above.
- [ ] Use/rework existing demo components with explicit data/actions interfaces; remove parallel simplified renderers as parity is achieved.
- [ ] Close data/API gaps before claiming UI features restored. Never substitute fake production records.
- [ ] Compare each page populated/empty/loading/error, each modal open/closed, each permitted role, and desktop/mobile layouts side by side.
- [ ] Test submit/retry/conflict/permission denial and keyboard/focus behavior against real backend boundaries.
- [ ] Preserve role landing/main menu decisions, real Auth, private evidence, database permissions, history and audit invariants.
- [ ] Run type checks, both builds, focused workflow/security tests and performance checks.
- [ ] Obtain review of screenshots/workflows before commit or deployment; no commit/push is authorized by this audit request.
