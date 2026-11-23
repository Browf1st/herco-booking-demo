# F-012: Staff access and roles
> Documented from existing docs on 2026-11-20 — owner to confirm.

**Status:** Needs answers (first Owner set up) · **Milestone:** M2 · **Depends on:** F-005

## In one sentence
The Owner gives each staff member exactly the pages and actions they need, and can turn access off, so nobody sees or changes more than their job requires.

## User steps (exactly how it works)
1. A project administrator sets up the first Owner once, using the guarded SQL in docs/staff-access.md (done 2026-11-20 on the hosted project).
2. The Owner signs in, opens **Account → Staff workspace → Staff access** (`/staff-access`).
3. Enters the exact email of an existing verified HERCO account and ticks page and action grants.
4. Disables access when it should end.

## Rules and details
- Roles mentioned: Owner, Superadmin, Admin, Staff. Owner decision 2026-11-23: roles are labels only; what someone can do comes from the ticked pages and actions, so "Restricted Admin" was removed from the form. Existing `restricted_admin` accounts keep their grants, show as Admin and are saved as `admin` when edited; the server still accepts the old value.
- Fix 2026-11-23: an action that belongs to two pages ("Complete bookings and attach photos" on Bookings and Booking history) is listed once in the form. Before, ticking both pages crashed the form and saving failed (`src/lib/live/staff-access-actions.ts`).
- Pages: Staff Access, Bookings, Change requests, Booking history, Customers, HERCO Points, Inventory, Reports, Pricing, Activity log.
- Actions: manageStaff, createBooking, manageSchedule, confirmBooking, cancelBooking, rescheduleBooking, editServices, adjustPrices, completeBooking, reviewCancellation, reviewReschedule, managePoints, manageRewards, approveRewards, claimRewards, manageInventory, viewIncome, changePricing, changePromotions.
- The Owner can only grant permissions they hold, and only to Admin and Staff. Owner and Superadmin assignments need a separately authorized project administrator.
- Every server request checks verified email, enabled membership and grants; a revoked grant takes effect on the next request.
- Staff sign in with password only (approved 2026-11-20); MFA optional.
- Every change is audited in `herco_private.staff_access_audit` (actor, target, time, before/after).
- Role-by-role permission matrix and who is Superadmin: TBD — ask owner (Q-11).

## Screens
- `/staff-access`: staff list, grant editor, disable toggle, errors for unknown or unverified email.
- Staff navigation shows only permitted sections.

## Data
- `herco_private.staff_memberships`, `herco_private.staff_access_audit`.

## API
- Staff access list and update endpoints. Paths TBD in api-contract.

## Edge cases and errors
- Email has no verified account → refused.
- Staff tries to promote themselves → refused.
- Second Owner bootstrap → refused.

## Must not break
- Owner access already granted; customer booking path.

## Acceptance tests (all must pass)
- [ ] Page-only, single-action, disabled and cross-shop staff are allowed/refused correctly by direct request.
- [ ] Owner cannot grant permissions they lack or edit another Owner.
- [ ] Non-staff cannot get workspace permissions (verified on hosted project).

## Ready checklist (no code until all are ticked and the owner approves)
- [x] Every user step is written out
- [ ] Rules, limits and permissions are decided
- [ ] Screens and their states are described
- [x] Data and API are designed
- [x] Edge cases and "must not break" are listed
- [x] Acceptance tests are written
- [ ] No open questions left
- [ ] **Owner approved:**
