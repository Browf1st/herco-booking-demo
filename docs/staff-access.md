# Set up staff access

After the database migrations are applied, create and verify a normal HERCO account for the shop owner in the intended environment. Confirm the email belongs to the intended owner. An authorized Supabase project administrator can assign the first Owner in the SQL editor using the transaction below.

Replace `verified-owner@example.test` with the verified email for that environment. Review the page and action arrays before running it. This example includes operational permissions that the Owner can delegate. Remove any grant the Owner should lack.

```sql
begin;
lock table herco_private.staff_memberships in share row exclusive mode;

do $$
declare
  verified_user uuid;
begin
  select id into strict verified_user from auth.users
  where lower(email) = lower('verified-owner@example.test') and email_confirmed_at is not null;

  if exists (select 1 from herco_private.staff_memberships where role = 'owner') then
    raise exception 'An Owner already exists. Use the authorized account recovery process.';
  end if;

  insert into herco_private.staff_memberships (user_id, role, enabled, page_grants, action_grants)
  values (
    verified_user, 'owner', true,
    array['Staff Access','Bookings','Change requests','Booking history','Customers','HERCO Points','Inventory','Reports','Pricing','Activity log'],
    array['manageStaff','createBooking','manageSchedule','confirmBooking','cancelBooking','rescheduleBooking',
      'editServices','adjustPrices','completeBooking','reviewCancellation','reviewReschedule','managePoints',
      'manageRewards','approveRewards','claimRewards','manageInventory','viewIncome','changePricing','changePromotions']
  );
end
$$;

commit;
```

The insert requires a verified account with no existing staff membership. If it fails, have the project administrator review the existing membership rather than replacing it by email alone. Record the bootstrap actor, target and timestamp in the deployment handoff.

1. Have the Owner sign in to the Worker app and enroll an authenticator on **Account**.
2. Verify the authenticator code and open **Staff access** from the staff workspace.
3. Grant access to staff, admins, and restricted admins using the exact email from each existing verified HERCO account. Select the pages and actions they need. Disable access when access should end.
4. Verify with separate staging accounts that the Owner can delegate only their own permissions and a lower role cannot access the management page or API.

Staff access updates record the actor, target, timestamp, and before and after permissions in `herco_private.staff_access_audit`. Assignments for privileged Owner and Superadmin identities require a separately authorized project administrator. If a privileged member loses an authenticator, use the Supabase account recovery process for their verified identity and record the change in the handoff.
