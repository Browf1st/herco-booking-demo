-- Approved password-only staff access. Preserve verified identities and scoped grants.
begin;

create function herco_private.has_verified_staff_session()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from auth.users u
    join herco_private.staff_memberships m on m.user_id=u.id
    where u.id=auth.uid() and u.email_confirmed_at is not null and m.enabled
  );
$$;
revoke all on function herco_private.has_verified_staff_session() from public, anon, authenticated;

create or replace function public.herco_set_availability(visit_date date, change text, visit_hour smallint default null)
returns void
language plpgsql volatile security definer set search_path = '' as $$
declare
  actor uuid := auth.uid();
  member herco_private.staff_memberships;
  shop_now timestamp;
begin
  if not herco_private.has_verified_staff_session() then
    raise exception 'Sign in with a verified staff account before changing availability.' using errcode = '42501';
  end if;

  select m.* into member from herco_private.staff_memberships as m
    where m.user_id = actor and m.enabled for share;
  if not found or ('Bookings' = any(member.page_grants) and 'manageSchedule' = any(member.action_grants)) is not true then
    raise exception 'You do not have permission to manage availability.' using errcode = '42501';
  end if;

  if visit_date is null or not isfinite(visit_date) or change is null
    or change not in ('open_date', 'close_date', 'restore_date', 'block_slot', 'unblock_slot')
    or (change in ('block_slot', 'unblock_slot') and (visit_hour is null or visit_hour not between 9 and 16))
    or (change in ('open_date', 'close_date', 'restore_date') and visit_hour is not null) then
    raise exception 'Choose a valid date and availability action.' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(72002, visit_date - date '2000-01-01');
  shop_now := clock_timestamp() at time zone 'Asia/Manila';
  if visit_date < shop_now::date
    or (change = 'block_slot' and visit_date + make_time(visit_hour, 0, 0) <= shop_now) then
    raise exception 'Choose a future appointment time.' using errcode = '22023';
  end if;

  case change
    when 'restore_date' then
      delete from herco_private.date_overrides as o where o.visit_date = herco_set_availability.visit_date;
    when 'block_slot' then
      insert into herco_private.slot_blocks values (visit_date, visit_hour) on conflict do nothing;
    when 'unblock_slot' then
      delete from herco_private.slot_blocks as s
        where s.visit_date = herco_set_availability.visit_date and s.visit_hour = herco_set_availability.visit_hour;
    else
      insert into herco_private.date_overrides as o values (visit_date, change = 'open_date')
      on conflict on constraint date_overrides_pkey do update set is_open = excluded.is_open
      where o.is_open is distinct from excluded.is_open;
  end case;
  if found then
    insert into herco_private.schedule_events (actor_id, visit_date, visit_hour, change)
    values (actor, visit_date, visit_hour, change);
  end if;
end
$$;

create or replace function herco_private.staff_booking_grants()
returns text[]
language plpgsql volatile set search_path = '' as $$
declare
  grants text[];
begin
  if not herco_private.has_verified_staff_session() then
    raise exception 'Sign in with a verified staff account first.' using errcode = '42501';
  end if;
  select m.action_grants into grants
  from herco_private.staff_memberships as m
  where m.user_id = auth.uid() and m.enabled and 'Bookings' = any (m.page_grants)
  for share;
  if not found then
    raise exception 'You do not have access to the booking queue.' using errcode = '42501';
  end if;
  return grants;
end
$$;

create or replace function herco_private.check_point_staff(action text)
returns void language plpgsql stable set search_path = '' as $$
begin
  if not herco_private.has_verified_staff_session() or not exists (
    select 1 from herco_private.staff_memberships s
    where s.user_id = auth.uid() and s.enabled and 'HERCO Points' = any(s.page_grants)
      and (action is null or action = any(s.action_grants))
  ) then
    raise exception 'Points access requires staff permission.' using errcode = '42501';
  end if;
end;
$$;

create or replace function herco_private.staff_change_grants()
returns text[]
language plpgsql volatile set search_path = '' as $$
declare grants text[];
begin
  if not herco_private.has_verified_staff_session() then
    raise exception 'Sign in with a verified staff account first.' using errcode = '42501';
  end if;
  select m.action_grants into grants from herco_private.staff_memberships m
    where m.user_id = auth.uid() and m.enabled and 'Change requests' = any (m.page_grants) for share;
  if not found then raise exception 'You do not have access to change requests.' using errcode = '42501'; end if;
  return grants;
end
$$;

create or replace function herco_private.check_inventory_staff(write_access boolean)
returns void language plpgsql stable set search_path = '' as $$
begin
  if not herco_private.has_verified_staff_session() or not exists (
    select 1 from herco_private.staff_memberships s
    where s.user_id = auth.uid() and s.enabled and 'Inventory' = any(s.page_grants)
      and (not write_access or 'manageInventory' = any(s.action_grants))
  ) then
    raise exception 'Inventory access requires staff permission.' using errcode = '42501';
  end if;
end;
$$;

create or replace function herco_private.require_completion_staff()
returns void language plpgsql stable set search_path = '' as $$
begin
  if not herco_private.has_verified_staff_session() or not exists (
    select 1 from herco_private.staff_memberships s where s.user_id = auth.uid() and s.enabled
      and s.page_grants && array['Bookings', 'Booking history']
      and 'completeBooking' = any(s.action_grants)
  ) then raise exception 'Staff completion permission is required.' using errcode = '42501'; end if;
end;
$$;

create or replace function public.herco_booking_report(from_date date, to_date date)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare actions text[];
  include_value boolean;
begin
  if not herco_private.has_verified_staff_session() then
    raise exception 'Reports require staff permission.' using errcode = '42501';
  end if;
  select s.action_grants into actions from herco_private.staff_memberships s
    where s.user_id = auth.uid() and s.enabled and 'Reports' = any(s.page_grants);
  if not found then raise exception 'This account cannot access reports.' using errcode = '42501'; end if;
  if from_date is null or to_date is null or to_date < from_date or to_date-from_date > 365 then
    raise exception 'Choose a date range of up to 366 days.' using errcode = '22023';
  end if;
  include_value := 'viewIncome' = any(actions);
  return (select jsonb_build_object('total',count(*),'pending',count(*) filter (where b.status='pending'),
    'booked',count(*) filter (where b.status='confirmed'),'cancelled',count(*) filter (where b.status='cancelled'),
    'completed',count(*) filter (where b.status='done'),
    'completedWithoutValue',case when include_value then count(*) filter (where b.status='done' and c.booking_id is null) end,
    'completedValueCentavos',case when include_value then coalesce(sum(coalesce(p.corrected_completed_centavos,c.final_price_centavos))
      filter (where b.status='done'),0) end,
    'valueCorrectionsCentavos',case when include_value then coalesce(sum(p.corrected_completed_centavos-c.final_price_centavos),0) end)
    from public.herco_bookings b left join herco_private.booking_completion c on c.booking_id=b.id
    left join lateral (select x.corrected_completed_centavos from herco_private.booking_price_corrections x
      where include_value and x.booking_id=b.id and x.corrected_completed_centavos is not null
      order by x.revision desc limit 1) p on true
    where b.visit_date between from_date and to_date);
end;
$$;

create or replace function public.herco_workspace_permissions()
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('role', s.role, 'pages', s.page_grants, 'actions', s.action_grants)
  from herco_private.staff_memberships s
  where s.enabled and s.user_id = auth.uid() and herco_private.has_verified_staff_session();
$$;

create or replace function herco_private.staff_management_actor()
returns herco_private.staff_memberships
language plpgsql volatile set search_path = '' as $$
declare
  member herco_private.staff_memberships;
begin
  if not herco_private.has_verified_staff_session() then
    raise exception 'Sign in with a verified staff account first.' using errcode = '42501';
  end if;

  select m.* into member from herco_private.staff_memberships m
  where m.user_id = auth.uid() and m.enabled and m.role in ('owner', 'superadmin')
    and 'Staff Access' = any(m.page_grants) and 'manageStaff' = any(m.action_grants)
  for share;
  if not found then
    raise exception 'You do not have access to manage staff.' using errcode = '42501';
  end if;
  return member;
end
$$;

create or replace function herco_private.pricing_grants()
returns text[]
language plpgsql volatile set search_path = '' as $$
declare grants text[];
begin
  if not herco_private.has_verified_staff_session() then
    raise exception 'Sign in with a verified staff account first.' using errcode = '42501';
  end if;
  select m.action_grants into grants
  from herco_private.staff_memberships as m
  where m.user_id = auth.uid() and m.enabled and 'Pricing' = any (m.page_grants)
  for share;
  if not found then
    raise exception 'You do not have access to pricing.' using errcode = '42501';
  end if;
  return grants;
end;
$$;

create or replace function herco_private.may_edit_booked_services(booking public.herco_bookings)
returns boolean language plpgsql volatile set search_path = '' as $$
declare
  is_staff boolean;
  shop_now timestamp := clock_timestamp() at time zone 'Asia/Manila';
begin
  if auth.uid() is null then
    raise exception 'Sign in to see the booking services.' using errcode = '42501';
  end if;
  if herco_private.has_verified_staff_session() then
    perform 1 from herco_private.staff_memberships s where s.user_id = auth.uid() and s.enabled
      and 'Bookings' = any(s.page_grants) and 'editServices' = any(s.action_grants) for share;
    is_staff := found;
  end if;
  if booking.customer_id is distinct from auth.uid() and is_staff is not true then
    raise exception 'You do not have access to these booking services.' using errcode = '42501';
  end if;
  return booking.status = 'pending' and case when booking.booking_kind = 'walk_in' then booking.visit_date = shop_now::date
      else booking.visit_date + make_time(booking.visit_hour, 0, 0) > shop_now end
    or (is_staff is true and booking.status in ('pending', 'confirmed') and booking.visit_date >= shop_now::date);
end
$$;

create or replace function herco_private.can_request_walk_in_intake(lock_grant boolean)
returns boolean
language plpgsql volatile set search_path = '' as $$
begin
  if not herco_private.has_verified_staff_session() then return false; end if;
  if lock_grant then
    perform 1 from herco_private.staff_memberships m
    where m.user_id = auth.uid() and m.enabled and 'Bookings' = any(m.page_grants)
      and 'createBooking' = any(m.action_grants) for share;
  else
    perform 1 from herco_private.staff_memberships m
    where m.user_id = auth.uid() and m.enabled and 'Bookings' = any(m.page_grants)
      and 'createBooking' = any(m.action_grants);
  end if;
  return found;
end
$$;

create or replace function public.herco_staff_activity(from_date date, through_date date)
returns table (recorded_at timestamptz, area text, action text, actor uuid, reference text)
language plpgsql stable security definer set search_path = '' as $$
declare starts timestamptz;
  ends timestamptz;
begin
  if not herco_private.has_verified_staff_session() or not exists (
    select 1 from herco_private.staff_memberships s where s.user_id = auth.uid() and s.enabled
      and s.role in ('owner', 'superadmin') and 'Activity log' = any(s.page_grants)
  ) then raise exception 'Activity log access requires Owner permission.' using errcode = '42501'; end if;
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

create or replace function herco_private.require_customers_page()
returns void
language plpgsql volatile set search_path = '' as $$
begin
  if not herco_private.has_verified_staff_session() then
    raise exception 'Sign in with a verified staff account first.' using errcode = '42501';
  end if;

  perform 1 from herco_private.staff_memberships as m
  where m.user_id = auth.uid() and m.enabled and 'Customers' = any (m.page_grants)
  for share;
  if not found then
    raise exception 'You do not have access to customers.' using errcode = '42501';
  end if;
end;
$$;

create or replace function herco_private.require_price_adjustment()
returns void language plpgsql volatile set search_path = '' as $$
begin
  if not herco_private.has_verified_staff_session() then
    raise exception 'Price corrections require a verified staff account.' using errcode = '42501';
  end if;
  perform 1 from herco_private.staff_memberships s where s.user_id = auth.uid() and s.enabled
    and s.page_grants && array['Bookings','Booking history'] and 'adjustPrices' = any(s.action_grants)
    for share;
  if not found then raise exception 'Price corrections require staff permission.' using errcode = '42501'; end if;
end;
$$;

notify pgrst, 'reload schema';
commit;
