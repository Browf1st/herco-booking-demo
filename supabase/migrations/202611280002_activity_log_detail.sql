-- Owner decision 2026-11-28: the Activity log's Bookings rows must say WHAT changed, not just "Services updated".
-- The Bookings branch now reads the detailed private tables (price edits, price corrections, service add/remove)
-- plus the meaningful status events, building a readable sentence and the HG-n reference. This mirrors the
-- per-booking "Changes" timeline (herco_booking_history). Every other module branch is unchanged.
-- Amounts appear only for an owner who also holds viewIncome (consistent with the rest of the app).
create or replace function public.herco_staff_activity(from_date date, through_date date)
returns table (recorded_at timestamptz, area text, action text, actor uuid, reference text)
language plpgsql stable security definer set search_path = '' as $$
declare starts timestamptz;
  ends timestamptz;
  show_money boolean;
begin
  if not herco_private.has_verified_staff_session() then
    raise exception 'Activity log access requires Owner permission.' using errcode = '42501'; end if;
  select ('viewIncome' = any(s.action_grants)) into show_money from herco_private.staff_memberships s
    where s.user_id = auth.uid() and s.enabled and s.role in ('owner', 'superadmin') and 'Activity log' = any(s.page_grants);
  if show_money is null then raise exception 'Activity log access requires Owner permission.' using errcode = '42501'; end if;
  if from_date is null or through_date is null or not isfinite(from_date) or not isfinite(through_date)
    or through_date < from_date or through_date - from_date > 30 then
    raise exception 'Choose a date range of up to 31 days.' using errcode = '22023';
  end if;
  starts := from_date::timestamp at time zone 'Asia/Manila';
  ends := (through_date + 1)::timestamp at time zone 'Asia/Manila';
  return query
    select e.recorded_at, e.area, e.action, e.actor, e.reference from (
      -- Bookings: one readable row per real change, newest first, with the HG-n reference.
      select bk.happened as recorded_at, 'Bookings'::text as area, bk.action, bk.actor_id as actor,
        'HG-' || b.reference_no::text as reference
      from (
        select pe.recorded_at as happened, pe.actor_id, pe.booking_id,
          pe.service_label || ' price ' ||
          case when show_money then '₱' || to_char(round(pe.previous_centavos / 100.0), 'FM999,999,999')
            || ' → ₱' || to_char(round(pe.new_centavos / 100.0), 'FM999,999,999') else 'changed' end as action
        from herco_private.booking_price_edits pe
        union all
        select pc.recorded_at, pc.actor_id, pc.booking_id,
          'Completed price corrected' ||
          case when show_money then ' ₱' || to_char(round(pc.previous_centavos / 100.0), 'FM999,999,999')
            || ' → ₱' || to_char(round(pc.corrected_centavos / 100.0), 'FM999,999,999') else '' end
        from herco_private.booking_price_corrections pc
        union all
        select s.recorded_at, s.actor_id, s.booking_id,
          'Added ' || coalesce(a->>'label', a->>'code') ||
          case when show_money and (a->>'price_centavos') is not null
            then ' (₱' || to_char(round((a->>'price_centavos')::bigint / 100.0), 'FM999,999,999') || ')' else '' end
        from herco_private.booking_service_changes s cross join lateral jsonb_array_elements(s.after_services) a
        where not exists (select 1 from jsonb_array_elements(s.before_services) o where o->>'code' = a->>'code')
        union all
        select s.recorded_at, s.actor_id, s.booking_id, 'Removed ' || coalesce(o->>'label', o->>'code')
        from herco_private.booking_service_changes s cross join lateral jsonb_array_elements(s.before_services) o
        where not exists (select 1 from jsonb_array_elements(s.after_services) a where a->>'code' = o->>'code')
        union all
        select ev.created_at, ev.actor_id, ev.booking_id,
          case when ev.kind in ('booking_submitted', 'walk_in_submitted', 'booking_created_by_staff') then 'Booked'
            when ev.kind in ('booking_confirmed', 'walk_in_confirmed') then 'Approved'
            when ev.kind = 'completed' then 'Completed'
            when ev.kind in ('booking_cancel_approved', 'booking_cancelled_by_staff') then 'Cancelled'
            else 'Rescheduled' end
        from public.herco_booking_events ev
        where ev.kind in ('booking_submitted', 'walk_in_submitted', 'booking_created_by_staff', 'booking_confirmed',
          'walk_in_confirmed', 'completed', 'booking_cancel_approved', 'booking_cancelled_by_staff',
          'booking_reschedule_approved', 'booking_rescheduled_by_staff')
      ) bk join public.herco_bookings b on b.id = bk.booking_id
      where bk.happened >= starts and bk.happened < ends
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
