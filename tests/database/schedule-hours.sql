-- F-002 opening hours. Run against a fresh local or CI database after every migration. Fictional data only.
begin;

-- Helpers (rolled back with the rest). refused() runs a statement and expects one SQLSTATE.
create function public.herco_test_refused(statement text, state text) returns void language plpgsql as $$
begin
  execute statement;
  raise exception 'NOT REFUSED: %', statement;
exception when others then
  if sqlstate is distinct from state then
    raise exception 'Expected % but got % (%) for: %', state, sqlstate, sqlerrm, statement;
  end if;
end $$;
-- A Wednesday 7-13 days ahead. Wednesday is open by default; Monday (wed - 2) is closed.
create function public.herco_test_wed() returns date language sql stable as $$
  select current_date + 7 + ((3 - extract(dow from current_date)::int + 7) % 7)
$$;

insert into auth.users(id,email,email_confirmed_at) values
  ('00000000-0000-4000-8000-000000000301','hours-manager@example.test',now()),
  ('00000000-0000-4000-8000-000000000302','hours-viewer@example.test',now()),
  ('00000000-0000-4000-8000-000000000304','hours-customer@example.test',now());
insert into herco_private.staff_memberships(user_id,role,page_grants,action_grants) values
  ('00000000-0000-4000-8000-000000000301','staff',array['Bookings','Change requests'],array['manageSchedule','rescheduleBooking','reviewReschedule']),
  ('00000000-0000-4000-8000-000000000302','staff',array['Bookings'],array['rescheduleBooking']);
update herco_private.services set enabled = true where code = 'ceramic';

-- 1. Defaults: nothing changes until staff save new hours (9 AM-5 PM, last slot 4 PM, Wednesday-Sunday).
do $$
declare
  wed date := public.herco_test_wed();
  shop_now timestamp := clock_timestamp() at time zone 'Asia/Manila';
begin
  if not exists (select 1 from herco_private.schedule_settings
    where open_hour = 9 and close_hour = 17 and open_weekdays = '{0,3,4,5,6}'::smallint[]) then raise exception 'Default settings changed'; end if;
  if array(select h from herco_private.day_hours(wed) as h order by h) <> '{9,10,11,12,13,14,15,16}'::smallint[] then
    raise exception 'Default Wednesday hours are not 9-16'; end if;
  if exists (select 1 from herco_private.day_hours(wed - 2)) then raise exception 'Monday is open by default'; end if;
  if herco_private.slot_status(wed, 10::smallint, shop_now) <> 'open' then raise exception '10 AM not open'; end if;
  if herco_private.slot_status(wed, 8::smallint, shop_now) <> 'closed' then raise exception '8 AM not closed'; end if;
  if herco_private.slot_status(wed, 17::smallint, shop_now) <> 'closed' then raise exception '5 PM not closed'; end if;
  if herco_private.slot_status(wed - 2, 10::smallint, shop_now) <> 'closed' then raise exception 'Monday 10 AM not closed'; end if;
  if (select count(*) from public.herco_availability(wed, wed) a where a.status = 'open' and a.visit_hour is not null) <> 8
    or (select min(a.open_hour) from public.herco_availability(wed, wed) a) <> 9
    or (select max(a.close_hour) from public.herco_availability(wed, wed) a) <> 17 then raise exception 'Availability for a default day is wrong'; end if;
  if not exists (select 1 from public.herco_availability(wed - 2, wed - 2) a
    where a.visit_hour is null and a.closed and a.status = 'closed') then raise exception 'Closed Monday not reported'; end if;
  if exists (select 1 from public.herco_availability(wed, wed) a where a.status = 'booked') then raise exception 'booked status returned'; end if;
end $$;

-- 2. Constraints reject bad data.
select public.herco_test_refused($s$insert into herco_private.slot_blocks values (current_date + 30, 24)$s$, '23514');
select public.herco_test_refused($s$insert into herco_private.slot_blocks values (current_date + 30, -1)$s$, '23514');
select public.herco_test_refused($s$insert into herco_private.date_overrides(visit_date,is_open,open_hour) values (current_date + 30, true, 8)$s$, '23514');
select public.herco_test_refused($s$insert into herco_private.date_overrides(visit_date,is_open,open_hour,close_hour) values (current_date + 30, true, 12, 12)$s$, '23514');
select public.herco_test_refused($s$insert into herco_private.date_overrides(visit_date,is_open,open_hour,close_hour) values (current_date + 30, false, 8, 12)$s$, '23514');
select public.herco_test_refused($s$insert into herco_private.date_overrides(visit_date,is_open,open_hour,close_hour) values (current_date + 30, true, 24, 25)$s$, '23514');
select public.herco_test_refused($s$update herco_private.schedule_settings set close_hour = open_hour$s$, '23514');
select public.herco_test_refused($s$update herco_private.schedule_settings set open_weekdays = '{}'$s$, '23514');
select public.herco_test_refused($s$update herco_private.schedule_settings set open_weekdays = '{7}'$s$, '23514');
select public.herco_test_refused($s$insert into herco_private.schedule_settings(singleton,open_hour,close_hour,open_weekdays) values (false,9,17,'{1}')$s$, '23514');
select public.herco_test_refused($s$insert into herco_private.schedule_settings(open_hour,close_hour,open_weekdays) values (9,17,'{1}')$s$, '23505');
insert into herco_private.slot_blocks values (current_date + 30, 0), (current_date + 30, 23);
delete from herco_private.slot_blocks where visit_date = current_date + 30;
-- Booking hours 0 and 23 are valid rows; 24 is not.
insert into public.herco_bookings (customer_id,request_id,request_payload,visit_date,visit_hour,bike,customer_contact,original_services,original_total_centavos)
  values ('00000000-0000-4000-8000-000000000304',gen_random_uuid(),'{}',current_date + 40,0,'Fixture bike','{}','[]',0),
    ('00000000-0000-4000-8000-000000000304',gen_random_uuid(),'{}',current_date + 40,23,'Fixture bike','{}','[]',0);
select public.herco_test_refused($s$insert into public.herco_bookings (customer_id,request_id,request_payload,visit_date,visit_hour,bike,customer_contact,original_services,original_total_centavos)
  values ('00000000-0000-4000-8000-000000000304',gen_random_uuid(),'{}',current_date + 40,24,'Fixture bike','{}','[]',0)$s$, '23514');

-- 3. No limit per hour: three bookings in one hour work; the retry key still stops double submits.
do $$
declare
  wed date := public.herco_test_wed();
  cust uuid := '00000000-0000-4000-8000-000000000304';
  retry uuid := gen_random_uuid();
begin
  perform herco_private.create_booking_for(cust, cust, false, gen_random_uuid(), wed, 10::smallint, array['ceramic'], 'Bike A', 'Fixture Name', '', '');
  perform herco_private.create_booking_for(cust, cust, false, gen_random_uuid(), wed, 10::smallint, array['ceramic'], 'Bike B', 'Fixture Name', '', '');
  perform herco_private.create_booking_for(cust, cust, false, retry, wed, 10::smallint, array['ceramic'], 'Bike C', 'Fixture Name', '', '');
  perform herco_private.create_booking_for(cust, cust, false, retry, wed, 10::smallint, array['ceramic'], 'Bike C', 'Fixture Name', '', '');
  if (select count(*) from public.herco_bookings where visit_date = wed and visit_hour = 10 and status <> 'cancelled') <> 3 then
    raise exception 'Expected three bookings in one hour and one booking for a retried request'; end if;
  if herco_private.slot_status(wed, 10::smallint, clock_timestamp() at time zone 'Asia/Manila') <> 'open' then
    raise exception 'A busy hour stopped being open'; end if;
  if (select count(*) from public.herco_availability(wed, wed) a where a.visit_hour = 10 and a.status = 'open') <> 1 then
    raise exception 'Customers should see the busy hour as Open'; end if;
end $$;

-- 4. Saves outside the date's hours are refused by the database itself (called directly).
select public.herco_test_refused(format($s$select herco_private.create_booking_for('00000000-0000-4000-8000-000000000304','00000000-0000-4000-8000-000000000304',false,gen_random_uuid(),%L,8::smallint,array['ceramic'],'Bike','Fixture Name','','')$s$, public.herco_test_wed()), '23P01');
select public.herco_test_refused(format($s$select herco_private.create_booking_for('00000000-0000-4000-8000-000000000304','00000000-0000-4000-8000-000000000304',false,gen_random_uuid(),%L,17::smallint,array['ceramic'],'Bike','Fixture Name','','')$s$, public.herco_test_wed()), '23P01');
select public.herco_test_refused(format($s$select herco_private.create_booking_for('00000000-0000-4000-8000-000000000304','00000000-0000-4000-8000-000000000304',false,gen_random_uuid(),%L,10::smallint,array['ceramic'],'Bike','Fixture Name','','')$s$, public.herco_test_wed() - 2), '23P01');
-- Staff manual booking path (same function, booked by staff).
select public.herco_test_refused(format($s$select herco_private.create_booking_for('00000000-0000-4000-8000-000000000301','00000000-0000-4000-8000-000000000304',true,gen_random_uuid(),%L,20::smallint,array['ceramic'],'Bike','Fixture Name','0917 000 0000','')$s$, public.herco_test_wed()), '23P01');
-- Hour outside 0-23 is invalid input.
select public.herco_test_refused(format($s$select herco_private.create_booking_for('00000000-0000-4000-8000-000000000304','00000000-0000-4000-8000-000000000304',false,gen_random_uuid(),%L,24::smallint,array['ceramic'],'Bike','Fixture Name','','')$s$, public.herco_test_wed()), '22023');

-- 5. Staff views: booked counts per hour and calendar data.
set local role authenticated;
select set_config('test.uid','00000000-0000-4000-8000-000000000302',true);
do $$
declare
  wed date := public.herco_test_wed();
  day_view jsonb := public.herco_staff_booking_day_with_options(wed);
  cal jsonb := public.herco_staff_calendar(wed - 2, wed);
begin
  if jsonb_array_length(day_view->'slots') <> 8 or (day_view->>'closed')::boolean then raise exception 'Staff day slots are not the 8 default hours'; end if;
  if (select (s->>'booked')::int from jsonb_array_elements(day_view->'slots') s where (s->>'hour')::int = 10) <> 3 then raise exception 'Staff day view should count 3 booked'; end if;
  if exists (select 1 from jsonb_array_elements(day_view->'slots') s where s->>'status' = 'booked') then raise exception 'booked slot status returned'; end if;
  if (day_view->>'open_hour')::int <> 9 or (day_view->>'close_hour')::int <> 17 then raise exception 'Staff day hours wrong'; end if;
  if exists (select 1 from jsonb_array_elements(day_view->'bookings') b where (b->>'outside_hours')::boolean) then raise exception 'Booking wrongly marked outside hours'; end if;
  if (cal->0->>'closed')::boolean is not true or (cal->2->>'closed')::boolean then raise exception 'Calendar closed flags wrong'; end if;
  if cal->2->'hours' <> '[{"hour": 10, "booked": 3}]'::jsonb then raise exception 'Calendar booked count per hour wrong: %', cal->2->'hours'; end if;
  if public.herco_staff_schedule_settings() - 'version' <> '{"openHour":9,"closeHour":17,"openWeekdays":[0,3,4,5,6],"canManage":false}'::jsonb
    or public.herco_staff_schedule_settings()->>'version' !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z$' then
    raise exception 'Staff without manageSchedule cannot read settings (or canManage is wrong): %', public.herco_staff_schedule_settings(); end if;
end $$;

-- 6. Permission refusals: staff without manageSchedule, a customer, and a signed-out caller.
select public.herco_test_refused($s$select public.herco_set_schedule_settings(8::smallint,20::smallint,array[0,3]::smallint[],false)$s$, '42501');
select public.herco_test_refused(format($s$select public.herco_set_date_hours(%L,8::smallint,12::smallint,false)$s$, public.herco_test_wed() + 14), '42501');
select public.herco_test_refused(format($s$select public.herco_set_availability(%L,'block_slot',10::smallint)$s$, public.herco_test_wed()), '42501');
select public.herco_test_refused($s$select * from herco_private.schedule_settings$s$, '42501');
select set_config('test.uid','00000000-0000-4000-8000-000000000304',true);
select public.herco_test_refused($s$select public.herco_staff_schedule_settings()$s$, '42501');
select public.herco_test_refused($s$select public.herco_set_schedule_settings(8::smallint,20::smallint,array[0,3]::smallint[],false)$s$, '42501');
select public.herco_test_refused(format($s$select public.herco_set_date_hours(%L,8::smallint,12::smallint,false)$s$, public.herco_test_wed() + 14), '42501');
reset role;
set local role anon;
select set_config('test.uid','',true);
select public.herco_test_refused($s$select public.herco_set_schedule_settings(8::smallint,20::smallint,array[0,3]::smallint[],false)$s$, '42501');
select public.herco_test_refused($s$select public.herco_staff_schedule_settings()$s$, '42501');
do $$ begin
  if (select count(*) from public.herco_availability(public.herco_test_wed(), public.herco_test_wed())) = 0 then raise exception 'Signed-out visitors lost public availability'; end if;
end $$;
reset role;

-- 7. Invalid input from a permitted manager: 22023 and nothing saved.
set local role authenticated;
select set_config('test.uid','00000000-0000-4000-8000-000000000301',true);
select public.herco_test_refused($s$select public.herco_set_schedule_settings(9::smallint,9::smallint,array[1]::smallint[],false)$s$, '22023');
select public.herco_test_refused($s$select public.herco_set_schedule_settings(12::smallint,9::smallint,array[1]::smallint[],false)$s$, '22023');
select public.herco_test_refused($s$select public.herco_set_schedule_settings(24::smallint,24::smallint,array[1]::smallint[],false)$s$, '22023');
select public.herco_test_refused($s$select public.herco_set_schedule_settings(9::smallint,25::smallint,array[1]::smallint[],false)$s$, '22023');
select public.herco_test_refused($s$select public.herco_set_schedule_settings(9::smallint,0::smallint,array[1]::smallint[],false)$s$, '22023');
select public.herco_test_refused($s$select public.herco_set_schedule_settings(9::smallint,17::smallint,array[]::smallint[],false)$s$, '22023');
select public.herco_test_refused($s$select public.herco_set_schedule_settings(9::smallint,17::smallint,array[7]::smallint[],false)$s$, '22023');
select public.herco_test_refused($s$select public.herco_set_schedule_settings(9::smallint,17::smallint,array[1,1]::smallint[],false)$s$, '22023');
select public.herco_test_refused($s$select public.herco_set_schedule_settings(9::smallint,17::smallint,null,false)$s$, '22023');
select public.herco_test_refused($s$select public.herco_set_schedule_settings(null,17::smallint,array[1]::smallint[],false)$s$, '22023');
select public.herco_test_refused(format($s$select public.herco_set_date_hours(%L,12::smallint,8::smallint,false)$s$, public.herco_test_wed() + 14), '22023');
select public.herco_test_refused(format($s$select public.herco_set_date_hours(%L,8::smallint,25::smallint,false)$s$, public.herco_test_wed() + 14), '22023');
-- Past dates and past hours cannot be changed.
select public.herco_test_refused($s$select public.herco_set_date_hours(current_date - 1,8::smallint,12::smallint,false)$s$, '22023');
select public.herco_test_refused(format($s$select public.herco_set_date_hours(%L,8::smallint,12::smallint,false,-1)$s$, public.herco_test_wed() + 14), '22023');
select public.herco_test_refused($s$select public.herco_set_schedule_settings(9::smallint,17::smallint,array[1]::smallint[],false,null,-1)$s$, '22023');
do $$ begin
  begin perform public.herco_set_date_hours(current_date - 1, 8::smallint, 12::smallint, false); raise exception 'Past date accepted';
  exception when sqlstate '22023' then
    if sqlerrm <> 'That date has passed.' then raise exception 'Wrong past-date message: %', sqlerrm; end if;
  end;
end $$;
select public.herco_test_refused($s$select public.herco_set_availability(current_date - 1,'close_date')$s$, '22023');
select public.herco_test_refused($s$select public.herco_set_availability(current_date - 1,'block_slot',10::smallint)$s$, '22023');
select public.herco_test_refused($s$select public.herco_set_availability(current_date - 1,'unblock_slot',10::smallint)$s$, '22023');
select public.herco_test_refused(format($s$select public.herco_set_availability(%L,'block_slot',24::smallint)$s$, public.herco_test_wed()), '22023');
select public.herco_test_refused(format($s$select public.herco_set_availability(%L,'open_date',10::smallint)$s$, public.herco_test_wed()), '22023');
do $$ begin
  if (public.herco_staff_schedule_settings()->>'openHour')::int <> 9 or (public.herco_staff_schedule_settings()->>'canManage')::boolean is not true then
    raise exception 'A refused save changed the settings'; end if;
end $$;

-- 8. New default hours 8 AM-8 PM.
do $$
declare res jsonb := public.herco_set_schedule_settings(8::smallint, 20::smallint, array[3,0,4,5,6]::smallint[], false);
begin
  if res - 'version' <> '{"saved":true,"openHour":8,"closeHour":20,"openWeekdays":[0,3,4,5,6],"outsideCount":0}'::jsonb
    or res->>'version' is distinct from public.herco_staff_schedule_settings()->>'version' then raise exception 'Unexpected save result %', res; end if;
  if public.herco_staff_schedule_settings() - 'version' <> '{"openHour":8,"closeHour":20,"openWeekdays":[0,3,4,5,6],"canManage":true}'::jsonb then raise exception 'New hours not stored'; end if;
end $$;
reset role;
do $$
declare
  wed date := public.herco_test_wed();
  cust uuid := '00000000-0000-4000-8000-000000000304';
begin
  if array(select h from herco_private.day_hours(wed) as h order by h) <> '{8,9,10,11,12,13,14,15,16,17,18,19}'::smallint[] then raise exception 'Hours are not 8-19'; end if;
  if (select count(*) from public.herco_availability(wed, wed) a where a.visit_hour is not null and a.status = 'open') <> 12 then raise exception '12 slots expected'; end if;
  perform herco_private.create_booking_for(cust, cust, false, gen_random_uuid(), wed, 19::smallint, array['ceramic'], 'Late bike', 'Fixture Name', '', '');
  perform herco_private.create_booking_for(cust, cust, false, gen_random_uuid(), wed, 8::smallint, array['ceramic'], 'Early bike', 'Fixture Name', '', '');
  begin
    perform herco_private.create_booking_for(cust, cust, false, gen_random_uuid(), wed, 20::smallint, array['ceramic'], 'Too late', 'Fixture Name', '', '');
    raise exception 'A booking at the closing hour was accepted';
  exception when sqlstate '23P01' then null; end;
  if not exists (select 1 from herco_private.schedule_events where change = 'set_default_hours'
    and actor_id = '00000000-0000-4000-8000-000000000301' and details->>'open_hour' = '8' and details->>'close_hour' = '20') then
    raise exception 'Default hours change was not logged'; end if;
end $$;

-- 9. Shortening hours: warning lists the 7 PM and 8 AM bookings; Save anyway keeps them and labels Outside hours.
set local role authenticated;
do $$
declare
  wed date := public.herco_test_wed();
  res jsonb := public.herco_set_schedule_settings(9::smallint, 17::smallint, array[0,3,4,5,6]::smallint[], false);
begin
  if (res->>'saved')::boolean or res->>'code' <> 'bookings_outside_hours' or (res->>'outsideCount')::int <> 2 then raise exception 'Expected a warning for 2 bookings: %', res; end if;
  if res->'bookings' <> jsonb_build_array(
    jsonb_build_object('reference', res->'bookings'->0->>'reference', 'date', wed, 'hour', 8),
    jsonb_build_object('reference', res->'bookings'->1->>'reference', 'date', wed, 'hour', 19)) then raise exception 'Warning list wrong: %', res->'bookings'; end if;
  if (res->'bookings'->0->>'reference') not like 'HG-%' or (select count(*) from jsonb_object_keys(res->'bookings'->0)) <> 3 then
    raise exception 'Warning list shape wrong (reference, date, hour only)'; end if;
  if (public.herco_staff_schedule_settings()->>'closeHour')::int <> 20 then raise exception 'A warned save changed the settings'; end if;
  res := public.herco_set_schedule_settings(9::smallint, 17::smallint, array[0,3,4,5,6]::smallint[], true);
  if not (res->>'saved')::boolean or (res->>'outsideCount')::int <> 2 then raise exception 'Save anyway failed: %', res; end if;
end $$;

-- 9b. Stale save protection (two tabs): a save with an old version changes nothing; the current version saves.
select set_config('test.old_version', public.herco_staff_schedule_settings()->>'version', true);
reset role;
update herco_private.schedule_settings set updated_at = updated_at + interval '1 second';
set local role authenticated;
do $$
declare
  old_version text := current_setting('test.old_version');
  res jsonb;
begin
  res := public.herco_set_schedule_settings(8::smallint, 18::smallint, array[0,3,4,5,6]::smallint[], false, old_version);
  if (res->>'saved')::boolean or res->>'code' <> 'schedule_changed' then raise exception 'Stale version was not refused: %', res; end if;
  if (public.herco_staff_schedule_settings()->>'openHour')::int <> 9 then raise exception 'A stale save changed the settings'; end if;
  if public.herco_staff_schedule_settings()->>'version' = old_version then raise exception 'Version did not move'; end if;
  res := public.herco_set_schedule_settings(9::smallint, 17::smallint, array[0,3,4,5,6]::smallint[], false,
    public.herco_staff_schedule_settings()->>'version');
  if not (res->>'saved')::boolean then raise exception 'Current version was refused: %', res; end if;
  res := public.herco_set_schedule_settings(9::smallint, 17::smallint, array[0,3,4,5,6]::smallint[], false, null);
  if not (res->>'saved')::boolean then raise exception 'A save without a version must still work: %', res; end if;
end $$;
do $$
declare
  wed date := public.herco_test_wed();
  day_view jsonb := public.herco_staff_booking_day_with_options(wed);
  cal jsonb := public.herco_staff_calendar(wed, wed);
begin
  if (select count(*) from jsonb_array_elements(day_view->'bookings') b where (b->>'outside_hours')::boolean) <> 2 then raise exception 'Outside hours label missing'; end if;
  if (cal->0->>'outside_hours')::int <> 2 then raise exception 'Calendar outside count wrong'; end if;
end $$;
reset role;
do $$ begin
  if (select count(*) from public.herco_bookings where visit_date = public.herco_test_wed() and status = 'pending') <> 5 then raise exception 'Shortening hours changed bookings'; end if;
end $$;

-- 10. Weekday change: unticking Wednesday closes Wednesdays, a Wednesday set Open stays open.
set local role authenticated;
do $$
declare
  wed date := public.herco_test_wed();
  res jsonb := public.herco_set_schedule_settings(9::smallint, 17::smallint, array[0,4,5,6]::smallint[], false);
begin
  if (res->>'saved')::boolean or (res->>'outsideCount')::int <> 3 then raise exception 'Expected 3 future bookings on the newly closed Wednesday: %', res; end if;
  -- Save anyway after more bookings appeared than the staff member saw: refused with the new list, nothing saved
  res := public.herco_set_schedule_settings(9::smallint, 17::smallint, array[0,4,5,6]::smallint[], true, null, 2);
  if (res->>'saved')::boolean or res->>'code' <> 'bookings_outside_hours' or (res->>'outsideCount')::int <> 3 then
    raise exception 'A stale Save anyway was not refused: %', res; end if;
  if (public.herco_staff_schedule_settings()->'openWeekdays') <> '[0,3,4,5,6]'::jsonb then raise exception 'Refused Save anyway changed the weekdays'; end if;
  -- confirmed count equal to (or above) the real count saves; null means no count check
  res := public.herco_set_schedule_settings(9::smallint, 17::smallint, array[0,4,5,6]::smallint[], true, null, 3);
  if not (res->>'saved')::boolean then raise exception 'Save anyway with the right count failed: %', res; end if;
  perform public.herco_set_availability(wed + 7, 'open_date');
end $$;
reset role;
do $$
declare wed date := public.herco_test_wed();
begin
  if exists (select 1 from herco_private.day_hours(wed)) then raise exception 'Wednesday should be closed'; end if;
  if exists (select 1 from herco_private.day_hours(wed + 14)) then raise exception 'Next-next Wednesday should be closed'; end if;
  if array(select h from herco_private.day_hours(wed + 7) as h order by h) <> '{9,10,11,12,13,14,15,16}'::smallint[] then
    raise exception 'A Wednesday set Open must use the default hours'; end if;
  if (select count(*) from public.herco_bookings where visit_date = wed and status = 'pending') <> 5 then raise exception 'Closing a weekday changed bookings'; end if;
end $$;

-- 11. Own hours for one date, blocks, restore.
set local role authenticated;
do $$
declare
  d date := public.herco_test_wed() + 14;
  res jsonb;
begin
  res := public.herco_set_date_hours(d, 8::smallint, 12::smallint, false);
  if not (res->>'saved')::boolean then raise exception 'Own hours not saved: %', res; end if;
  perform public.herco_set_date_hours(d, 8::smallint, 12::smallint, false); -- same value again: no new log row
end $$;
reset role;
do $$
declare
  d date := public.herco_test_wed() + 14;
  cust uuid := '00000000-0000-4000-8000-000000000304';
  shop_now timestamp := clock_timestamp() at time zone 'Asia/Manila';
begin
  if array(select h from herco_private.day_hours(d) as h order by h) <> '{8,9,10,11}'::smallint[] then raise exception 'Own hours not 8-11'; end if;
  if herco_private.slot_status(d, 11::smallint, shop_now) <> 'open' or herco_private.slot_status(d, 12::smallint, shop_now) <> 'closed' then
    raise exception 'Own-hours edge hours wrong'; end if;
  if (select count(*) from herco_private.schedule_events where change = 'set_date_hours' and visit_date = d) <> 1 then raise exception 'Own hours logged wrong number of times'; end if;
  if (select count(*) from public.herco_availability(d, d) a where a.visit_hour is not null) <> 4 then raise exception 'Customers should see 4 slots'; end if;
  perform herco_private.create_booking_for(cust, cust, false, gen_random_uuid(), d, 11::smallint, array['ceramic'], 'Own hours bike', 'Fixture Name', '', '');
  begin
    perform herco_private.create_booking_for(cust, cust, false, gen_random_uuid(), d, 12::smallint, array['ceramic'], 'Too late', 'Fixture Name', '', '');
    raise exception 'A booking after the own closing hour was accepted';
  exception when sqlstate '23P01' then null; end;
end $$;
set local role authenticated;
do $$
declare
  d date := public.herco_test_wed() + 14;
  res jsonb := public.herco_set_date_hours(d, 8::smallint, 10::smallint, false);
begin
  if (res->>'saved')::boolean or (res->>'outsideCount')::int <> 1 or res->'bookings'->0->>'hour' <> '11' then raise exception 'Own-hours warning wrong: %', res; end if;
  res := public.herco_set_date_hours(d, 8::smallint, 10::smallint, true, 0);
  if (res->>'saved')::boolean or res->>'code' <> 'bookings_outside_hours' or (res->>'outsideCount')::int <> 1 then
    raise exception 'A stale own-hours Save anyway was not refused: %', res; end if;
  res := public.herco_set_date_hours(d, 8::smallint, 10::smallint, true, 1);
  if not (res->>'saved')::boolean then raise exception 'Own hours Save anyway failed'; end if;
  -- block, restore and closed choices
  perform public.herco_set_availability(d, 'block_slot', 9::smallint);
  perform public.herco_set_availability(d, 'close_date');   -- closed clears the own hours
  perform public.herco_set_availability(d, 'restore_date'); -- back to the weekday rule (closed)
end $$;
reset role;
do $$
declare d date := public.herco_test_wed() + 14;
begin
  if exists (select 1 from herco_private.date_overrides where visit_date = d) then raise exception 'restore_date left the override'; end if;
  if not exists (select 1 from herco_private.slot_blocks where visit_date = d and visit_hour = 9) then raise exception 'restore_date removed a manual block'; end if;
  if exists (select 1 from herco_private.day_hours(d)) then raise exception 'Restored date should follow the closed weekday'; end if;
  if not exists (select 1 from public.herco_bookings where visit_date = d and visit_hour = 11 and status = 'pending') then raise exception 'Date changes affected a booking'; end if;
end $$;

-- 12. Blocks: a blocked hour refuses bookings; a block outside the hours has no effect and returns later.
set local role authenticated;
do $$
declare d date := public.herco_test_wed() + 7;
begin
  perform public.herco_set_availability(d, 'block_slot', 10::smallint);
  perform public.herco_set_availability(d, 'block_slot', 20::smallint);
end $$;
reset role;
do $$
declare
  d date := public.herco_test_wed() + 7;
  cust uuid := '00000000-0000-4000-8000-000000000304';
  shop_now timestamp := clock_timestamp() at time zone 'Asia/Manila';
begin
  if herco_private.slot_status(d, 10::smallint, shop_now) <> 'blocked' then raise exception '10 AM not blocked'; end if;
  if herco_private.slot_status(d, 20::smallint, shop_now) <> 'closed' then raise exception 'A block outside hours must read closed'; end if;
  if exists (select 1 from public.herco_availability(d, d) a where a.visit_hour = 10) then raise exception 'Blocked hour is still offered'; end if;
  begin
    perform herco_private.create_booking_for(cust, cust, false, gen_random_uuid(), d, 10::smallint, array['ceramic'], 'Blocked', 'Fixture Name', '', '');
    raise exception 'A booking in a blocked hour was accepted';
  exception when sqlstate '23P01' then null; end;
end $$;
set local role authenticated;
select public.herco_set_availability(public.herco_test_wed() + 7, 'unblock_slot', 10::smallint);
reset role;
do $$
declare
  d date := public.herco_test_wed() + 7;
  cust uuid := '00000000-0000-4000-8000-000000000304';
begin
  perform herco_private.create_booking_for(cust, cust, false, gen_random_uuid(), d, 10::smallint, array['ceramic'], 'Reopened', 'Fixture Name', '', '');
  -- Hours grow again: the old block at 8 PM comes back into effect.
  update herco_private.schedule_settings set close_hour = 21;
  if herco_private.slot_status(d, 20::smallint, clock_timestamp() at time zone 'Asia/Manila') <> 'blocked' then raise exception 'Old block did not return'; end if;
  update herco_private.schedule_settings set close_hour = 17;
end $$;

-- 13. Change paths: customer request, staff approval and staff direct change are checked against the hours.
do $$
declare
  d date := public.herco_test_wed() + 7;
begin
  perform set_config('test.booking', (select id::text from public.herco_bookings where visit_date = d and bike = 'Reopened'), true);
end $$;
set local role authenticated;
select set_config('test.uid','00000000-0000-4000-8000-000000000304',true);
select public.herco_test_refused(format($s$select public.herco_request_booking_change(%L,gen_random_uuid(),'reschedule','',%L,20::smallint)$s$, current_setting('test.booking'), public.herco_test_wed() + 7), '23P01');
select set_config('test.request', public.herco_request_booking_change(current_setting('test.booking')::uuid, gen_random_uuid(), 'reschedule', '', public.herco_test_wed() + 7, 12::smallint)::text, true);
reset role;
insert into herco_private.slot_blocks values (public.herco_test_wed() + 7, 12);
set local role authenticated;
select set_config('test.uid','00000000-0000-4000-8000-000000000301',true);
select public.herco_test_refused(format($s$select public.herco_review_booking_change(%L,'approved')$s$, current_setting('test.request')), '23P01');
select public.herco_review_booking_change(current_setting('test.request')::uuid, 'declined');
select public.herco_test_refused(format($s$select public.herco_staff_change_booking(%L,gen_random_uuid(),'reschedule',%L,10::smallint,'',%L,20::smallint)$s$, current_setting('test.booking'), public.herco_test_wed() + 7, public.herco_test_wed() + 7), '23P01');
select public.herco_test_refused(format($s$select public.herco_staff_change_booking(%L,gen_random_uuid(),'reschedule',%L,10::smallint,'',%L,12::smallint)$s$, current_setting('test.booking'), public.herco_test_wed() + 7, public.herco_test_wed() + 7), '23P01');
select public.herco_staff_change_booking(current_setting('test.booking')::uuid, gen_random_uuid(), 'reschedule', public.herco_test_wed() + 7, 10::smallint, '', public.herco_test_wed() + 7, 13::smallint);
reset role;
do $$ begin
  if (select visit_hour from public.herco_bookings where id = current_setting('test.booking')::uuid) <> 13 then raise exception 'Valid staff reschedule did not apply'; end if;
end $$;

-- 14. Hours are checked again at save time: a booking save after the admin closes the hour is refused.
do $$
declare
  d date := public.herco_test_wed() + 7;
  cust uuid := '00000000-0000-4000-8000-000000000304';
begin
  delete from herco_private.slot_blocks where visit_date = d and visit_hour = 12;
  perform herco_private.create_booking_for(cust, cust, false, gen_random_uuid(), d, 12::smallint, array['ceramic'], 'Before close', 'Fixture Name', '', '');
  insert into herco_private.slot_blocks values (d, 14);
  begin
    perform herco_private.create_booking_for(cust, cust, false, gen_random_uuid(), d, 14::smallint, array['ceramic'], 'After close', 'Fixture Name', '', '');
    raise exception 'Booking was saved after the hour was blocked';
  exception when sqlstate '23P01' then null; end;
  if (select count(*) from public.herco_bookings b join herco_private.slot_blocks s
    on s.visit_date = b.visit_date and s.visit_hour = b.visit_hour where b.visit_date = d and b.bike = 'After close') <> 0 then
    raise exception 'A booking exists in a blocked hour'; end if;
end $$;

-- 15. Every change is in the schedule log with who.
do $$ begin
  if (select count(*) from herco_private.schedule_events where change = 'set_default_hours') <> 3 then raise exception 'Default-hours changes not all logged'; end if;
  if exists (select 1 from herco_private.schedule_events where actor_id is null) then raise exception 'Unattributed log row'; end if;
  if not exists (select 1 from herco_private.schedule_events where change in ('open_date','block_slot','unblock_slot','close_date','restore_date')) then raise exception 'Date changes not logged'; end if;
end $$;

rollback;
