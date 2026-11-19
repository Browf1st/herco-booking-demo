begin;

-- Customers can read their own booking timeline through the existing RLS rule.
-- Keep internal actor identifiers private.
revoke select on public.herco_booking_events from authenticated;
grant select (id, booking_id, kind, to_status, created_at) on public.herco_booking_events to authenticated;

create function public.herco_staff_activity(from_date date, through_date date)
returns table (recorded_at timestamptz, area text, action text, actor uuid, reference text)
language plpgsql stable security definer set search_path = '' as $$
declare starts timestamptz;
  ends timestamptz;
begin
  if (auth.jwt()->>'aal') is distinct from 'aal2' or not exists (
    select 1 from herco_private.staff_memberships s where s.user_id = auth.uid() and s.enabled
      and s.role in ('owner', 'superadmin') and 'Activity log' = any(s.page_grants)
  ) then raise exception 'Activity log access requires Owner permission and MFA.' using errcode = '42501'; end if;
  if from_date is null or through_date is null or not isfinite(from_date) or not isfinite(through_date)
    or through_date < from_date or through_date - from_date > 30 then
    raise exception 'Choose a date range of up to 31 days.' using errcode = '22023';
  end if;
  starts := from_date::timestamp at time zone 'Asia/Manila';
  ends := (through_date + 1)::timestamp at time zone 'Asia/Manila';
  return query
    select e.recorded_at, e.area, e.action, e.actor, e.reference from (
      select b.created_at as recorded_at, 'Bookings'::text as area, b.kind as action,
        b.actor_id as actor, b.booking_id::text as reference from public.herco_booking_events b
        where b.created_at >= starts and b.created_at < ends
      union all
      select s.created_at, 'Availability', s.change, s.actor_id, s.visit_date::text from herco_private.schedule_events s
        where s.created_at >= starts and s.created_at < ends
      union all
      select i.recorded_at, 'Inventory', i.operation, i.actor_id, i.stock_id::text from herco_private.stock_activity i
        where i.recorded_at >= starts and i.recorded_at < ends
      union all
      select p.recorded_at, 'Pricing', p.setting, p.actor_id, p.request_id::text from herco_private.pricing_audit p
        where p.recorded_at >= starts and p.recorded_at < ends
      union all
      select sa.occurred_at, 'Staff access', 'membership_updated', sa.actor_id, sa.target_id::text
        from herco_private.staff_access_audit sa where sa.occurred_at >= starts and sa.occurred_at < ends
      union all
      select pe.created_at, 'HERCO Points', case when pe.receipt_id is null then 'points_adjusted' else 'reward_redeemed' end,
        pe.actor_id, coalesce(pe.receipt_id, pe.member_id)::text from herco_private.point_entries pe
        where pe.created_at >= starts and pe.created_at < ends
      union all
      select r.approved_at, 'HERCO Points', 'reward_approved', r.approved_by, r.id::text from herco_private.point_receipts r
        where r.approved_at >= starts and r.approved_at < ends
      union all
      select r.claimed_at, 'HERCO Points', 'reward_claimed', r.claimed_by, r.id::text from herco_private.point_receipts r
        where r.claimed_at >= starts and r.claimed_at < ends
    ) e order by e.recorded_at desc, e.area, e.reference, e.action, e.actor limit 100;
end;
$$;

revoke all on function public.herco_staff_activity(date, date) from public, anon, authenticated;
grant execute on function public.herco_staff_activity(date, date) to authenticated;

commit;
