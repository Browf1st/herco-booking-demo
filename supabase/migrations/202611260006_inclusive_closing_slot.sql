-- Inclusive closing slot: the closing hour itself is now bookable (closeHour 17 gives slots 9:00 ... 17:00).
-- OWNER-AUTHORIZED HOSTED RELEASE STEP: apply together with the Worker/screen changes that stop assuming "closeHour - 1".
-- Only the DERIVED last bookable slot changes. The stored open/close hours keep their meaning (close 1-24, after open).
-- A closing hour of 24 still ends at 23:00 (hour 24 does not exist). This only ADDS a slot per open day: no booking
-- becomes outside hours, nothing is moved, cancelled or re-priced.
-- Every hour check (create, edit, reschedule, manual, walk-in, guest, block) goes through slot_status -> day_hours -> window_hours,
-- so changing window_hours widens them all. The other functions below had their own "closeHour - 1" or "max hour + 1" arithmetic.
-- `close_hour` in availability, the staff day view and the calendar stays the date's CLOSING hour (17), not the last slot start.
begin;

create or replace function herco_private.window_hours(day date, open_h smallint, close_h smallint, weekdays smallint[])
returns setof smallint language sql stable set search_path = '' as $$
  select g::smallint
  from (select 1) as one
  left join herco_private.date_overrides as o on o.visit_date = day
  cross join lateral generate_series(coalesce(o.open_hour, open_h)::integer, least(coalesce(o.close_hour, close_h)::integer, 23)) as g
  where coalesce(o.is_open, extract(dow from day)::smallint = any (weekdays))
$$;

create or replace function public.herco_availability(from_date date, to_date date)
returns table (visit_date date, visit_hour smallint, status text, open_hour smallint, close_hour smallint, closed boolean)
language plpgsql stable security definer set search_path = '' as $$
declare
  shop_now timestamp := statement_timestamp() at time zone 'Asia/Manila';
begin
  if from_date is null or to_date is null or from_date < shop_now::date - 31
    or to_date < from_date or to_date - from_date > 41 or to_date > shop_now::date + 365 then
    raise exception 'Choose up to 42 dates within the booking calendar.' using errcode = '22023';
  end if;

  return query
    with days as (
      select (from_date + n)::date as d from generate_series(0, to_date - from_date) as n
    ), hours as (
      select days.d, w.hour,
        (days.d + make_time(w.hour::integer, 0, 0) > shop_now
          and not exists (select 1 from herco_private.slot_blocks as s where s.visit_date = days.d and s.visit_hour = w.hour)) as bookable
      from days cross join lateral herco_private.day_hours(days.d) as w(hour)
    ), bounds as (
      select h.d, min(h.hour) as first_hour,
        (select coalesce(o.close_hour, s.close_hour) from herco_private.schedule_settings as s
          left join herco_private.date_overrides as o on o.visit_date = h.d) as end_hour
      from hours as h group by h.d
    )
    select days.d, h.hour, 'open'::text, b.first_hour::smallint, b.end_hour::smallint, false
    from days join bounds as b on b.d = days.d
    join hours as h on h.d = days.d and h.bookable
    union all
    select days.d, null::smallint, 'closed'::text, b.first_hour::smallint, b.end_hour::smallint, b.d is null
    from days left join bounds as b on b.d = days.d
    where not exists (select 1 from hours as h where h.d = days.d and h.bookable)
    order by 1, 2;
end
$$;

create or replace function public.herco_set_date_hours(
  p_date date, p_open_hour smallint, p_close_hour smallint, p_confirm_outside boolean default false,
  p_confirmed_outside integer default null
)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  actor uuid := herco_private.require_schedule_manager();
  shop_now timestamp;
  outside_count bigint;
  listed jsonb;
begin
  if p_date is null or not isfinite(p_date) or p_open_hour is null or p_close_hour is null
    or p_open_hour not between 0 and 23 or p_close_hour not between 1 and 24 or p_close_hour <= p_open_hour then
    raise exception 'Closing time must be after opening time.' using errcode = '22023';
  end if;

  if p_confirmed_outside is not null and p_confirmed_outside < 0 then
    raise exception 'Check the confirmation choice.' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(72002, p_date - date '2000-01-01');
  shop_now := clock_timestamp() at time zone 'Asia/Manila';
  if p_date < shop_now::date then
    raise exception 'That date has passed.' using errcode = '22023';
  end if;

  with hit as (
    select b.reference_no, b.visit_date, b.visit_hour
    from public.herco_bookings as b
    where b.visit_date = p_date and b.status <> 'cancelled' and b.visit_hour is not null
      and b.visit_date + make_time(b.visit_hour, 0, 0) > shop_now
      and exists (select 1 from herco_private.day_hours(b.visit_date) as o(hour) where o.hour = b.visit_hour)
      and b.visit_hour not between p_open_hour and least(p_close_hour, 23)
  ), numbered as (
    select h.*, row_number() over (order by h.visit_hour, h.reference_no) as rn from hit as h
  )
  select (select count(*) from hit),
    coalesce(jsonb_agg(jsonb_build_object('reference', 'HG-' || n.reference_no, 'date', n.visit_date, 'hour', n.visit_hour)
      order by n.rn) filter (where n.rn <= 100), '[]'::jsonb)
  into outside_count, listed from numbered as n;

  if outside_count > 0 and (p_confirm_outside is not true or outside_count > coalesce(p_confirmed_outside, outside_count)) then
    return jsonb_build_object('saved', false, 'code', 'bookings_outside_hours',
      'outsideCount', outside_count, 'bookings', listed);
  end if;

  insert into herco_private.date_overrides as o (visit_date, is_open, open_hour, close_hour)
  values (p_date, true, p_open_hour, p_close_hour)
  on conflict on constraint date_overrides_pkey do update
    set is_open = true, open_hour = excluded.open_hour, close_hour = excluded.close_hour
    where (o.is_open, o.open_hour, o.close_hour) is distinct from (true, excluded.open_hour, excluded.close_hour);
  if found then
    insert into herco_private.schedule_events (actor_id, visit_date, change, details)
    values (actor, p_date, 'set_date_hours', jsonb_build_object(
      'open_hour', p_open_hour, 'close_hour', p_close_hour, 'outside_count', outside_count));
  end if;
  return jsonb_build_object('saved', true, 'outsideCount', outside_count);
end
$$;

create or replace function public.herco_staff_booking_day(visit_date date)
returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  grants text[] := herco_private.staff_booking_grants();
  shop_now timestamp := statement_timestamp() at time zone 'Asia/Manila';
  day date := visit_date;
  override_open boolean;
  own_open smallint;
  own_close smallint;
  win_open integer;
  win_close integer;
  items jsonb;
  slots jsonb;
begin
  if visit_date is null or not isfinite(visit_date) then
    raise exception 'Choose a valid calendar date.' using errcode = '22023';
  end if;

  select o.is_open, o.open_hour, o.close_hour into override_open, own_open, own_close
    from herco_private.date_overrides as o where o.visit_date = day;
  select jsonb_agg(jsonb_build_object(
    'id', b.id,
    'visit_hour', b.visit_hour,
    'bike', b.bike,
    'customer_name', b.customer_contact->>'name',
    'customer_phone', b.customer_contact->>'phone',
    'status', b.status,
    'services', (select jsonb_agg(s->>'label') from jsonb_array_elements(coalesce(b.current_services, b.original_services)) as s),
    'approval_note', n.body,
    'request_pending', exists (select 1 from herco_private.booking_change_requests r
      where r.booking_id = b.id and r.state = 'pending'),
    'outside_hours', herco_private.is_outside_hours(b.visit_date, b.visit_hour)
  ) order by b.visit_hour, b.id)
  into items
  from public.herco_bookings b
  left join herco_private.booking_approval_notes n on n.booking_id = b.id
  where b.visit_date = day and b.status <> 'cancelled';

  select jsonb_agg(jsonb_build_object(
    'hour', h.hour,
    'status', herco_private.slot_status(day, h.hour, shop_now),
    'blocked', exists (
      select 1 from herco_private.slot_blocks s where s.visit_date = day and s.visit_hour = h.hour
    ),
    'booked', (select count(*) from public.herco_bookings b
      where b.visit_date = day and b.visit_hour = h.hour and b.status <> 'cancelled')
  ) order by h.hour), min(h.hour), min(h.hour)
  into slots, win_open, win_close
  from herco_private.day_hours(day) as h(hour);
  -- the date's closing hour (the last slot now starts AT it): its own hours, else the default
  win_close := case when win_open is null then null else coalesce(own_close, (select s.close_hour from herco_private.schedule_settings as s)) end;

  return jsonb_build_object(
    'bookings', coalesce(items, '[]'::jsonb),
    'slots', coalesce(slots, '[]'::jsonb),
    'override', override_open,
    'closed', win_open is null,
    'open_hour', win_open,
    'close_hour', win_close,
    'own_open_hour', own_open,
    'own_close_hour', own_close,
    'can_confirm', 'confirmBooking' = any (grants),
    'can_cancel', 'cancelBooking' = any (grants),
    'can_reschedule', 'rescheduleBooking' = any (grants),
    'can_edit_services', 'editServices' = any (grants),
    'can_manage_schedule', 'manageSchedule' = any (grants),
    'can_view_points', exists (
      select 1 from herco_private.staff_memberships m
      where m.user_id = auth.uid() and m.enabled and 'HERCO Points' = any (m.page_grants)
    ),
    'past_date', visit_date < shop_now::date
  );
end
$$;

create or replace function public.herco_staff_calendar(from_date date,through_date date)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare result jsonb;
begin
  perform herco_private.staff_booking_grants();
  if from_date is null or through_date is null or through_date<from_date or through_date-from_date>62 then
    raise exception 'Choose up to 63 calendar dates.' using errcode='22023';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('date',day::date,
    'pending',(select count(*) from public.herco_bookings b where b.visit_date=day::date and b.status='pending'),
    'booked',(select count(*) from public.herco_bookings b where b.visit_date=day::date and b.status='confirmed'),
    'completed',(select count(*) from public.herco_bookings b where b.visit_date=day::date and b.status='done'),
    'closed',not exists (select 1 from herco_private.day_hours(day::date)),
    'open_hour',(select min(h.hour) from herco_private.day_hours(day::date) as h(hour)),
    'close_hour',(select case when exists (select 1 from herco_private.day_hours(day::date)) then coalesce((select o.close_hour from herco_private.date_overrides o where o.visit_date=day::date),(select s.close_hour from herco_private.schedule_settings s)) end),
    'outside_hours',(select count(*) from public.herco_bookings b where b.visit_date=day::date and b.status<>'cancelled'
      and herco_private.is_outside_hours(b.visit_date,b.visit_hour)),
    'hours',(select coalesce(jsonb_agg(jsonb_build_object('hour',x.visit_hour,'booked',x.n) order by x.visit_hour),'[]')
      from (select b.visit_hour,count(*) as n from public.herco_bookings b
        where b.visit_date=day::date and b.status<>'cancelled' and b.visit_hour is not null group by b.visit_hour) x)
    ) order by day),'[]') into result
  from generate_series(from_date::timestamp,through_date::timestamp,'1 day'::interval) day;
  return result;
end;
$$;

notify pgrst,'reload schema';
commit;
