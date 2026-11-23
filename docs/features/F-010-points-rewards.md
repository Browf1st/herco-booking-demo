# F-010: HERCO Points and rewards
> Documented from existing docs on 2026-11-20 — owner to confirm.

**Status:** Needs answers · **Milestone:** M2 · **Depends on:** F-005, F-012

## In one sentence
Customers earn HERCO Points and redeem them for rewards, and staff award points and record reward claims, so loyal customers are rewarded fairly.

## User steps (exactly how it works)
1. Customer opens `/points` to see their balance, ranking and available rewards.
   - Staff ranking (`/staff-points`, owner decision 2026-11-23): the # number is always the fan's points rank (highest points = #1), also when sorted by fewest points or name, or while searching. Fans outside the loaded top 500 show "–".
2. Customer redeems a reward; a redemption record is created.
3. Staff open `/staff-points` to award or correct points, manage rewards, approve redemptions and mark rewards as claimed.
4. History shows member, reward, points, dates and which staff member handled the claim.

## Rules and details
- Grants: `managePoints`, `manageRewards`, `approveRewards`, `claimRewards`; page HERCO Points.
- Ledger-based: every change is an entry; balances checked and locked; no double redemption or repeat claims.
- Earlier points and reward history stay unchanged when settings change.
- Handoff: points are awarded and corrected by hand. Production plan mentions preventing duplicate completion rewards (automatic). TBD — ask owner (Q-14).
- Point values, rewards catalog, expiry: TBD — ask owner (Q-14).
- Page type is smaller since 2026-11-20 (owner request): title about 32-40px, section titles about 20-24px, balance about 29px.
- Current build (checked in code 2026-11-20): a completed booking earns no points automatically. Points change only when staff add or remove them by hand with a reason, or when a customer redeems a reward.

## Screens
- `/points` (customer): balance, rewards, history, empty state.
- Reward rows (approved 2026-11-23): the reward name sits on the left and wraps to at most 2 lines (then "…", full name on hover), with the cost ("1,000 pts") on the right of the same line. Used for the signed-in reward cards and the signed-out "Rewards to work toward" list, in both builds (`RewardHeading`).
- `/staff-points` (staff): award/correct, rewards list, redemption approvals and claims.

## Data
- Points ledger, rewards, redemptions, claims (migrations exist; TEST rewards seeded).

## API
- Points balance/history, redeem, staff award/correct, approve, claim. Paths TBD in api-contract.

## Edge cases and errors
- Redeem with too few points → refused.
- Two redemptions at once on the same balance → only valid ones succeed.
- Claim twice → second refused.

## Must not break
- Customer directory points display (F-007), reports (F-011).

## Acceptance tests (all must pass)
- [ ] Concurrent redemptions cannot overdraw a balance (hosted PostgreSQL).
- [ ] Duplicate award or claim requests apply once.
- [ ] Claims show the verified staff member.
- [ ] Customers see only their own points.

## Ready checklist (no code until all are ticked and the owner approves)
- [x] Every user step is written out
- [ ] Rules, limits and permissions are decided
- [ ] Screens and their states are described
- [ ] Data and API are designed
- [x] Edge cases and "must not break" are listed
- [x] Acceptance tests are written
- [ ] No open questions left
- [ ] **Owner approved:**
