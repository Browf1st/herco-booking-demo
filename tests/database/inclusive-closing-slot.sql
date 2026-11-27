-- Inclusive closing slot (migration 202611260006): the closing hour is bookable. Default shop: 9 AM-5 PM, Wednesday-Sunday.
-- Run against a fresh local or CI database after every migration. Fictional data only; everything is rolled back.
begin;

create function public.herco_test_refused(statement text, state text) returns void language plpgsql as $$
begin
  execute statement;
  raise exception 'NOT REFUSED: %', statement;
exception when others then
  if sqlstate is distinct from state then
    raise exception 'Expected % but got % (%) for: %', state, sqlstate, sqlerrm, statement;
  end if;
end $$;
-- A Wednesday 7-13 days ahead (open by default).
create function public.herco_test_wed() returns date language sql stable as $$
  select current_date + 7 + ((3 - extract(dow from current_date)::int + 7) % 7)
$$;

insert into auth.users(id,email,email_confirmed_at) values
  ('00000000-0000-4000-8000-000000000751','ic-manager@example.test',now()),
  ('00000000-0000-4000-8000-000000000752','ic-customer@example.test',now());
insert into herco_private.staff_memberships(user_id,role,page_grants,action_grants) values
  ('00000000-0000-4000-8000-000000000751','staff',array['Bookings'],array['manageSchedule']);
update herco_private.services set enabled = true where code = 'ceramic';

-- Defaults are still 9 and 17 (stored meaning unchanged).
do $$ begin
  if not exists (select 1 from herco_private.schedule_settings where open_hour = 9 and close_hour = 17 and open_weekdays = '{0,3,4,5,6}'::smallint[]) then
    raise exception 'Default settings changed'; end if;
end $$;

-- An existing booking at 4 PM, made before anything else.
do $$
declare cust uuid := '00000000-0000-4000-8000-000000000752';
begin
  perform herco_private.create_booking_for(cust, cust, false, gen_random_uuid(), public.herco_test_wed(), 16::smallint, array['ceramic'], 'Existing 4PM', 'Fixture Name', '', '');
end $$;
select set_config('ic.before',(select md5(string_agg(b.id::text||b.visit_hour::text||b.status,',' order by b.id)) from public.herco_bookings b where b.bike='Existing 4PM'),true);

-- 1. Availability (what customers see, readable signed out): hours 9..17 open, opens 9, closes 17.
set local role anon;
select set_config('test.uid','',true);
do $$
declare wed date := public.herco_test_wed();
begin
  if array(select a.visit_hour from public.herco_availability(wed, wed) a where a.visit_hour is not null and a.status = 'open' order by 1) <> '{9,10,11,12,13,14,15,16,17}'::smallint[] then
    raise exception 'Hour 17 is not offered: %', array(select a.visit_hour from public.herco_availability(wed, wed) a order by 1); end if;
  if (select min(a.open_hour) from public.herco_availability(wed, wed) a) <> 9 or (select max(a.close_hour) from public.herco_availability(wed, wed) a) <> 17 then
    raise exception 'Availability should still report 9 and a closing hour of 17'; end if;
  if exists (select 1 from public.herco_availability(wed, wed) a where a.visit_hour = 18) then raise exception 'Hour 18 offered'; end if;
end $$;
reset role;

-- 2. Booking at 17 is accepted; 18 and 8 are still refused (23P01); the status function agrees.
do $$
declare
  wed date := public.herco_test_wed();
  cust uuid := '00000000-0000-4000-8000-000000000752';
  shop_now timestamp := clock_timestamp() at time zone 'Asia/Manila';
begin
  if herco_private.slot_status(wed, 17::smallint, shop_now) <> 'open' or herco_private.slot_status(wed, 18::smallint, shop_now) <> 'closed'
    or herco_private.slot_status(wed, 8::smallint, shop_now) <> 'closed' then raise exception 'slot_status disagrees'; end if;
  perform herco_private.create_booking_for(cust, cust, false, gen_random_uuid(), wed, 17::smallint, array['ceramic'], 'Closing hour', 'Fixture Name', '', '');
  if not exists (select 1 from public.herco_bookings where visit_date = wed and visit_hour = 17 and bike = 'Closing hour') then raise exception 'Booking at 17 not saved'; end if;
end $$;
select public.herco_test_refused(format($s$select herco_private.create_booking_for('00000000-0000-4000-8000-000000000752','00000000-0000-4000-8000-000000000752',false,gen_random_uuid(),%L,18::smallint,array['ceramic'],'Late','Fixture Name','','')$s$, public.herco_test_wed()), '23P01');
select public.herco_test_refused(format($s$select herco_private.create_booking_for('00000000-0000-4000-8000-000000000752','00000000-0000-4000-8000-000000000752',false,gen_random_uuid(),%L,8::smallint,array['ceramic'],'Early','Fixture Name','','')$s$, public.herco_test_wed()), '23P01');
-- A closed weekday still takes nothing at 17.
select public.herco_test_refused(format($s$select herco_private.create_booking_for('00000000-0000-4000-8000-000000000752','00000000-0000-4000-8000-000000000752',false,gen_random_uuid(),%L,17::smallint,array['ceramic'],'Closed day','Fixture Name','','')$s$, public.herco_test_wed() - 2), '23P01');

-- 3. Staff day view and calendar: the 17:00 slot is listed, the booking at 17 is inside hours.
set local role authenticated;
select set_config('test.uid','00000000-0000-4000-8000-000000000751',true);
do $$
declare
  wed date := public.herco_test_wed();
  day_view jsonb := public.herco_staff_booking_day_with_options(wed);
  cal jsonb := public.herco_staff_calendar(wed, wed);
begin
  if (select array_agg((s->>'hour')::int order by (s->>'hour')::int) from jsonb_array_elements(day_view->'slots') s) <> array[9,10,11,12,13,14,15,16,17] then
    raise exception 'Day view slots wrong: %', day_view->'slots'; end if;
  if (select s->>'status' from jsonb_array_elements(day_view->'slots') s where (s->>'hour')::int = 17) <> 'open'
    or (select (s->>'booked')::int from jsonb_array_elements(day_view->'slots') s where (s->>'hour')::int = 17) <> 1 then raise exception '17:00 slot wrong'; end if;
  if (day_view->>'open_hour')::int <> 9 or (day_view->>'close_hour')::int <> 17 or (day_view->>'closed')::boolean then raise exception 'Day hours wrong: %', day_view; end if;
  if exists (select 1 from jsonb_array_elements(day_view->'bookings') b where (b->>'outside_hours')::boolean) then raise exception 'A booking is marked outside hours'; end if;
  if (cal->0->>'outside_hours')::int <> 0 or (cal->0->>'close_hour')::int <> 17 or (cal->0->>'open_hour')::int <> 9
    or cal->0->'hours' <> '[{"hour": 16, "booked": 1}, {"hour": 17, "booked": 1}]'::jsonb then raise exception 'Calendar wrong: %', cal->0; end if;
  -- a closed date reports no hours
  if (public.herco_staff_calendar(wed - 2, wed - 2)->0->>'close_hour') is not null or (public.herco_staff_booking_day(wed - 2)->>'close_hour') is not null then
    raise exception 'A closed day should have no hours'; end if;
  -- blocking the closing hour works
  perform public.herco_set_availability(wed + 7, 'block_slot', 17::smallint);
end $$;
reset role;
do $$ begin
  if herco_private.slot_status(public.herco_test_wed() + 7, 17::smallint, clock_timestamp() at time zone 'Asia/Manila') <> 'blocked' then raise exception '17:00 could not be blocked'; end if;
end $$;

-- 4. Changing hours: the 5 PM booking is inside 9-17 (no warning) and outside 9-16 (warning), and own hours follow the same rule.
set local role authenticated;
select set_config('test.uid','00000000-0000-4000-8000-000000000751',true);
do $$
declare
  wed date := public.herco_test_wed();
  res jsonb;
begin
  res := public.herco_set_schedule_settings(9::smallint, 17::smallint, array[0,3,4,5,6]::smallint[], false);
  if not (res->>'saved')::boolean or (res->>'outsideCount')::int <> 0 then raise exception 'Same hours should save with no outside bookings: %', res; end if;
  res := public.herco_set_schedule_settings(9::smallint, 16::smallint, array[0,3,4,5,6]::smallint[], false);
  if (res->>'saved')::boolean or res->>'code' <> 'bookings_outside_hours' or (res->>'outsideCount')::int <> 1 or res->'bookings'->0->>'hour' <> '17' then
    raise exception 'Closing at 4 PM should warn about the 5 PM booking: %', res; end if;
  res := public.herco_set_date_hours(wed, 9::smallint, 17::smallint, false);
  if not (res->>'saved')::boolean or (res->>'outsideCount')::int <> 0 then raise exception 'Own hours 9-17 should include 5 PM: %', res; end if;
  res := public.herco_set_date_hours(wed, 9::smallint, 16::smallint, false);
  if (res->>'saved')::boolean or (res->>'outsideCount')::int <> 1 then raise exception 'Own hours 9-16 should exclude 5 PM: %', res; end if;
end $$;
reset role;

-- 5. A closing hour of 24 still ends at 23:00 (there is no hour 24); nothing breaks.
do $$
declare wed date := public.herco_test_wed() + 21;
begin
  update herco_private.schedule_settings set close_hour = 24;
  if array(select h from herco_private.day_hours(wed) as h order by h) <> '{9,10,11,12,13,14,15,16,17,18,19,20,21,22,23}'::smallint[] then raise exception 'Close 24 hours wrong'; end if;
  if (select max(a.close_hour) from public.herco_availability(wed, wed) a) <> 24 then raise exception 'Close 24 should be reported as 24'; end if;
  update herco_private.schedule_settings set close_hour = 17;
end $$;

-- 6. Existing bookings are untouched, and none became "outside hours".
do $$ begin
  if (select md5(string_agg(b.id::text||b.visit_hour::text||b.status,',' order by b.id)) from public.herco_bookings b where b.bike='Existing 4PM') <> current_setting('ic.before') then
    raise exception 'An existing booking changed'; end if;
  if exists (select 1 from public.herco_bookings b where b.status <> 'cancelled' and b.visit_hour is not null
    and b.visit_date = public.herco_test_wed() and herco_private.is_outside_hours(b.visit_date, b.visit_hour)) then raise exception 'A booking is outside hours'; end if;
end $$;

rollback;
