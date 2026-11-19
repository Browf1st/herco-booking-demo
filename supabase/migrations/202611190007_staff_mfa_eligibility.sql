begin;

-- Enrollment happens before AAL2. Expose only the current account's eligibility.
create function public.herco_may_enroll_staff_mfa()
returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from herco_private.staff_memberships membership
    where membership.user_id = auth.uid() and membership.enabled
  )
$$;

revoke all on function public.herco_may_enroll_staff_mfa() from public, anon, authenticated;
grant execute on function public.herco_may_enroll_staff_mfa() to authenticated;

commit;
