-- F-002: admin-set opening hours, open weekdays, own hours per date, no limit per hour.
-- Additive. Until staff save new hours the shop behaves as before: 9 AM-5 PM (last slot 4 PM), Wednesday-Sunday.
-- Run on local or staging first. Applying to hosted Supabase is a separate, approved release step.
begin;

------------------------------------------------------------------ tables
create table herco_private.schedule_settings (
  singleton boolean primary key default true check (singleton),
  open_hour smallint not null check (open_hour between 0 and 23),
  close_hour smallint not null check (close_hour between 1 and 24),
  open_weekdays smallint[] not null
    check (cardinality(open_weekdays) between 1 and 7 and open_weekdays <@ '{0,1,2,3,4,5,6}'::smallint[]),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id),
  check (close_hour > open_hour)
);
insert into herco_private.schedule_settings (open_hour, close_hour, open_weekdays) values (9, 17, '{0,3,4,5,6}');
alter table herco_private.schedule_settings enable row level security;
revoke all on herco_private.schedule_settings from public, anon, authenticated;

alter table herco_private.date_overrides
  add column open_hour smallint check (open_hour between 0 and 23),
  add column close_hour smallint check (close_hour between 1 and 24),
  add constraint date_overrides_hours_pair check ((open_hour is null) = (close_hour is null)),
  add constraint date_overrides_hours_order check (open_hour is null or close_hour > open_hour),
  add constraint date_overrides_hours_open check (open_hour is null or is_open);

-- What changed (hours, weekdays, counts). Default-hours events use the Manila date of the change as visit_date.
alter table herco_private.schedule_events add column details jsonb;

------------------------------------------------------------------ widen hour checks 9-16 -> 0-23
do $$
declare
  c record;
  remaining integer;
begin
  for c in
    select con.conrelid::regclass as tbl, con.conname, pg_get_constraintdef(con.oid) as def
    from pg_constraint con
    where con.contype = 'c'
      and con.conrelid in ('public.herco_bookings'::regclass, 'herco_private.slot_blocks'::regclass,
        'herco_private.booking_change_requests'::regclass)
      and pg_get_constraintdef(con.oid) ~ '_hour >= 9\) AND \(\w+_hour <= 16\)'
  loop
    execute format('alter table %s drop constraint %I', c.tbl, c.conname);
    execute format('alter table %s add constraint %I %s', c.tbl, c.conname,
      regexp_replace(c.def, '(_hour >= )9(\) AND \(\w+_hour <= )16', '\10\223'));
  end loop;
  select count(*) into remaining from pg_constraint con
    where con.contype = 'c'
      and con.conrelid in ('public.herco_bookings'::regclass, 'herco_private.slot_blocks'::regclass,
        'herco_private.booking_change_requests'::regclass)
      and pg_get_constraintdef(con.oid) ~ '_hour <= 16\)';
  if remaining <> 0 then raise exception 'A 9-16 hour check was not widened'; end if;
end
$$;

------------------------------------------------------------------ no limit per hour
drop index public.herco_active_booking_slot;
create index herco_active_booking_hour on public.herco_bookings (visit_date, visit_hour)
  where status <> 'cancelled' and visit_hour is not null;

------------------------------------------------------------------ hours rules
-- Hours a date is open for the given settings. A date's own row wins; otherwise the weekday decides.
create function herco_private.window_hours(day date, open_h smallint, close_h smallint, weekdays smallint[])
returns setof smallint language sql stable set search_path = '' as $$
  select g::smallint
  from (select 1) as one
  left join herco_private.date_overrides as o on o.visit_date = day
  cross join lateral generate_series(coalesce(o.open_hour, open_h)::integer, coalesce(o.close_hour, close_h)::integer - 1) as g
  where coalesce(o.is_open, extract(dow from day)::smallint = any (weekdays))
$$;

-- Bookable start hours of a date (before manual blocks and before the past is removed).
create function herco_private.day_hours(day date)
returns setof smallint language sql stable set search_path = '' as $$
  select w.hour
  from herco_private.schedule_settings as s
  cross join lateral herco_private.window_hours(day, s.open_hour, s.close_hour, s.open_weekdays) as w(hour)
$$;

create function herco_private.is_outside_hours(p_day date, p_hour smallint)
returns boolean language sql stable set search_path = '' as $$
  select p_hour is not null and not exists (
    select 1 from herco_private.day_hours(p_day) as h(hour) where h.hour = p_hour)
$$;

-- Every save path that sets a visit hour already calls slot_status inside its per-date lock, so
-- this one function now enforces the date's real hours and blocks for all of them.
create or replace function herco_private.slot_status(day date, hour smallint, shop_now timestamp)
returns text language sql stable set search_path = '' as $$
  select case
    when day + make_time(hour, 0, 0) <= shop_now then 'past'
    when not exists (select 1 from herco_private.day_hours(day) as h(hr) where h.hr = hour) then 'closed'
    when exists (
      select 1 from herco_private.slot_blocks as s where s.visit_date = day and s.visit_hour = hour
    ) then 'blocked'
    else 'open'
  end
$$;

revoke all on function herco_private.window_hours(date, smallint, smallint, smallint[]),
  herco_private.day_hours(date), herco_private.is_outside_hours(date, smallint)
  from public, anon, authenticated;

------------------------------------------------------------------ other functions: 9-16 -> 0-23
-- Re-create the latest live version of every function that still checks "between 9 and 16".
do $$
declare
  fn record;
  remaining integer;
begin
  for fn in
    select p.oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'herco_private') and p.prokind = 'f' and p.prosrc like '%between 9 and 16%'
  loop
    execute replace(pg_get_functiondef(fn.oid), 'between 9 and 16', 'between 0 and 23');
  end loop;
  select count(*) into remaining from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'herco_private') and p.prosrc like '%between 9 and 16%';
  if remaining <> 0 then raise exception 'A function still checks hours 9-16'; end if;
end
$$;

------------------------------------------------------------------ public availability
-- Only hours the shop can take are listed (status open). A date with no open hour returns one row with
-- visit_hour null: closed = true when the date is closed, false when every hour is past or blocked.
drop function public.herco_availability(date, date);
create function public.herco_availability(from_date date, to_date date)
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
      select h.d, min(h.hour) as first_hour, max(h.hour) + 1 as end_hour from hours as h group by h.d
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
revoke all on function public.herco_availability(date, date) from public, anon, authenticated;
grant execute on function public.herco_availability(date, date) to anon, authenticated;

------------------------------------------------------------------ staff schedule changes
create function herco_private.require_schedule_manager()
returns uuid language plpgsql volatile set search_path = '' as $$
begin
  if ('manageSchedule' = any (herco_private.staff_booking_grants())) is not true then
    raise exception 'You don''t have permission to change the schedule.' using errcode = '42501';
  end if;
  return auth.uid();
end
$$;
revoke all on function herco_private.require_schedule_manager() from public, anon, authenticated;

-- Version of the default hours: the last save time as an ISO string. Used to refuse a stale save (two tabs).
create function herco_private.schedule_version(saved_at timestamptz)
returns text language sql stable set search_path = '' as $$
  select to_char(saved_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
$$;
revoke all on function herco_private.schedule_version(timestamptz) from public, anon, authenticated;

create function public.herco_staff_schedule_settings()
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  grants text[] := herco_private.staff_booking_grants();
begin
  return (select jsonb_build_object('openHour', s.open_hour, 'closeHour', s.close_hour,
    'openWeekdays', to_jsonb(s.open_weekdays), 'canManage', 'manageSchedule' = any (grants),
    'version', herco_private.schedule_version(s.updated_at))
    from herco_private.schedule_settings as s);
end
$$;

-- Default hours and open weekdays. Returns saved=false with the bookings that would become outside
-- hours until confirm_outside is true (and, when confirmed_outside is given, until the recomputed count is
-- no higher than the count the staff member saw). p_version (optional) must match the current version, or
-- nothing is saved and code 'schedule_changed' is returned. Existing bookings are never moved or cancelled.
create function public.herco_set_schedule_settings(
  p_open_hour smallint, p_close_hour smallint, p_open_weekdays smallint[], p_confirm_outside boolean default false,
  p_version text default null, p_confirmed_outside integer default null
)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  actor uuid := herco_private.require_schedule_manager();
  shop_now timestamp := clock_timestamp() at time zone 'Asia/Manila';
  previous herco_private.schedule_settings;
  days smallint[];
  outside_count bigint;
  listed jsonb;
  new_version text;
begin
  if p_open_hour is null or p_close_hour is null or p_open_weekdays is null
    or p_open_hour not between 0 and 23 or p_close_hour not between 1 and 24 then
    raise exception 'Choose an opening and closing hour.' using errcode = '22023';
  end if;
  if p_close_hour <= p_open_hour then
    raise exception 'Closing time must be after opening time.' using errcode = '22023';
  end if;
  if cardinality(p_open_weekdays) not between 1 and 7 or array_position(p_open_weekdays, null) is not null
    or not (p_open_weekdays <@ '{0,1,2,3,4,5,6}'::smallint[])
    or (select count(distinct x) from unnest(p_open_weekdays) as x) <> cardinality(p_open_weekdays) then
    raise exception 'Pick at least one open day.' using errcode = '22023';
  end if;
  if p_confirmed_outside is not null and p_confirmed_outside < 0 then
    raise exception 'Check the confirmation choice.' using errcode = '22023';
  end if;
  days := array(select distinct x from unnest(p_open_weekdays) as x order by x);

  select s.* into previous from herco_private.schedule_settings as s for update;
  if not found then raise exception 'Opening hours are not set up.' using errcode = '55000'; end if;
  if p_version is not null and p_version is distinct from herco_private.schedule_version(previous.updated_at) then
    return jsonb_build_object('saved', false, 'code', 'schedule_changed');
  end if;

  with hit as (
    select b.reference_no, b.visit_date, b.visit_hour
    from public.herco_bookings as b
    where b.status <> 'cancelled' and b.visit_hour is not null and b.visit_date >= shop_now::date
      and b.visit_date + make_time(b.visit_hour, 0, 0) > shop_now
      and exists (select 1 from herco_private.day_hours(b.visit_date) as o(hour) where o.hour = b.visit_hour)
      and not exists (select 1 from herco_private.window_hours(b.visit_date, p_open_hour, p_close_hour, days) as n(hour)
        where n.hour = b.visit_hour)
  ), numbered as (
    select h.*, row_number() over (order by h.visit_date, h.visit_hour, h.reference_no) as rn from hit as h
  )
  select (select count(*) from hit),
    coalesce(jsonb_agg(jsonb_build_object('reference', 'HG-' || n.reference_no, 'date', n.visit_date, 'hour', n.visit_hour)
      order by n.rn) filter (where n.rn <= 100), '[]'::jsonb)
  into outside_count, listed from numbered as n;

  if outside_count > 0 and (p_confirm_outside is not true or outside_count > coalesce(p_confirmed_outside, outside_count)) then
    return jsonb_build_object('saved', false, 'code', 'bookings_outside_hours',
      'outsideCount', outside_count, 'bookings', listed);
  end if;

  if (previous.open_hour, previous.close_hour, previous.open_weekdays) is distinct from (p_open_hour, p_close_hour, days) then
    update herco_private.schedule_settings
      set open_hour = p_open_hour, close_hour = p_close_hour, open_weekdays = days, updated_at = now(), updated_by = actor;
    insert into herco_private.schedule_events (actor_id, visit_date, change, details)
    values (actor, shop_now::date, 'set_default_hours', jsonb_build_object(
      'open_hour', p_open_hour, 'close_hour', p_close_hour, 'open_weekdays', to_jsonb(days),
      'previous_open_hour', previous.open_hour, 'previous_close_hour', previous.close_hour,
      'previous_open_weekdays', to_jsonb(previous.open_weekdays), 'outside_count', outside_count));
  end if;
  select herco_private.schedule_version(s.updated_at) into new_version from herco_private.schedule_settings as s;
  return jsonb_build_object('saved', true, 'openHour', p_open_hour, 'closeHour', p_close_hour,
    'openWeekdays', to_jsonb(days), 'outsideCount', outside_count, 'version', new_version);
end
$$;

-- Own opening hours for one date (restore_date clears them).
create function public.herco_set_date_hours(
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
      and b.visit_hour not between p_open_hour and p_close_hour - 1
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

-- Same signature as before. open_date/close_date now also clear the date's own hours; restore_date removes
-- the whole override (closed/open choice and own hours); manual blocks are only changed by block/unblock.
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
    or (change in ('block_slot', 'unblock_slot') and (visit_hour is null or visit_hour not between 0 and 23))
    or (change in ('open_date', 'close_date', 'restore_date') and visit_hour is not null) then
    raise exception 'Choose a valid date and availability action.' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(72002, visit_date - date '2000-01-01');
  shop_now := clock_timestamp() at time zone 'Asia/Manila';
  if visit_date < shop_now::date
    or (change in ('block_slot', 'unblock_slot') and visit_date + make_time(visit_hour, 0, 0) <= shop_now) then
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
      insert into herco_private.date_overrides as o (visit_date, is_open) values (visit_date, change = 'open_date')
      on conflict on constraint date_overrides_pkey do update
        set is_open = excluded.is_open, open_hour = null, close_hour = null
        where (o.is_open, o.open_hour, o.close_hour) is distinct from (excluded.is_open, null::smallint, null::smallint);
  end case;
  if found then
    insert into herco_private.schedule_events (actor_id, visit_date, visit_hour, change)
    values (actor, visit_date, visit_hour, change);
  end if;
end
$$;

revoke all on function public.herco_staff_schedule_settings(),
  public.herco_set_schedule_settings(smallint, smallint, smallint[], boolean, text, integer),
  public.herco_set_date_hours(date, smallint, smallint, boolean, integer)
  from public, anon, authenticated;
grant execute on function public.herco_staff_schedule_settings(),
  public.herco_set_schedule_settings(smallint, smallint, smallint[], boolean, text, integer),
  public.herco_set_date_hours(date, smallint, smallint, boolean, integer)
  to authenticated;

------------------------------------------------------------------ staff day view and calendar
-- Latest version (0016) with: slots from the date's real hours, booked count per hour,
-- date hours and an Outside hours flag. Existing keys are unchanged; slot status is never 'booked' now.
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
  ) order by h.hour), min(h.hour), max(h.hour) + 1
  into slots, win_open, win_close
  from herco_private.day_hours(day) as h(hour);

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

create or replace function public.herco_staff_booking_day_with_options(visit_date date)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare result jsonb:=public.herco_staff_booking_day(visit_date); items jsonb;
begin
  select coalesce(jsonb_agg(herco_private.staff_booking_record(b)
      || jsonb_build_object('outside_hours', herco_private.is_outside_hours(b.visit_date, b.visit_hour))
    order by b.visit_hour nulls first, b.created_at),'[]') into items
  from public.herco_bookings b where b.visit_date=herco_staff_booking_day_with_options.visit_date and b.status<>'cancelled';
  return jsonb_set(result,'{bookings}',items);
end;
$$;

-- Latest version (0034) plus: closed follows the date's real hours, the date's hours,
-- booked count per hour (every non-cancelled booking) and how many bookings are outside hours.
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
    'close_hour',(select max(h.hour)+1 from herco_private.day_hours(day::date) as h(hour)),
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

-- Final guard: no function still builds the fixed 9-16 hours.
do $$
begin
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'herco_private') and p.prosrc like '%generate_series(9, 16)%') then
    raise exception 'A function still builds the fixed 9-16 hours';
  end if;
end
$$;

commit;
