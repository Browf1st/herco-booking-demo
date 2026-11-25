-- Fictional records only. Run after migrations against a local test database.
begin;

insert into auth.users (id, email, email_confirmed_at) values
  ('00000000-0000-4000-8000-000000000801', 'guest-staff@example.test', now()),
  ('00000000-0000-4000-8000-000000000802', 'guest-history@example.test', now()),
  ('00000000-0000-4000-8000-000000000803', 'guest-customer@example.test', now()),
  ('00000000-0000-4000-8000-000000000804', 'guest-directory@example.test', now()),
  ('00000000-0000-4000-8000-000000000805', 'guest-no-create@example.test', now());

insert into herco_private.staff_memberships (user_id, role, page_grants, action_grants) values
  ('00000000-0000-4000-8000-000000000801', 'owner', array['Bookings','Customers'], array['createBooking','confirmBooking','rescheduleBooking','cancelBooking','completeBooking']),
  ('00000000-0000-4000-8000-000000000802', 'staff', array['Booking history'], array[]::text[]),
  ('00000000-0000-4000-8000-000000000804', 'staff', array['Customers'], array[]::text[]),
  ('00000000-0000-4000-8000-000000000805', 'staff', array['Bookings'], array[]::text[]);

insert into herco_private.services (code, label, price_centavos, enabled)
values ('guest-fixture', 'Guest fixture service', 10000, true);
insert into herco_private.services (code, label, price_centavos, enabled, quote_required)
values ('guest-quote', 'Guest quote-only fixture', 0, true, true);
update herco_private.booking_promotion set enabled = true, discount_basis_points = 1000;
update herco_private.schedule_settings set open_hour = 8, close_hour = 17;
insert into herco_private.date_overrides (visit_date, is_open)
select (now() at time zone 'Asia/Manila')::date + days, true from generate_series(1, 4) days;
insert into herco_private.slot_blocks (visit_date, visit_hour)
values ((now() at time zone 'Asia/Manila')::date + 4, 8);

insert into public.herco_bookings (customer_id, request_id, request_payload, visit_date, visit_hour,
  bike, customer_contact, original_services, original_total_centavos)
values ('00000000-0000-4000-8000-000000000803', gen_random_uuid(), '{}',
  (now() at time zone 'Asia/Manila')::date + 1, 9, 'Existing bike',
  '{"name":"Fixture Mara Villanueva","email":"guest-customer@example.test"}',
  '[{"code":"guest-fixture","label":"Guest fixture service","price_centavos":10000}]', 10000);

insert into herco_private.walk_in_forms (version, title, body, signature_method, approved_by, approved_at, active)
values ('guest-regression-test', 'Test form', 'Fictional intake wording.', 'typed_name',
  '00000000-0000-4000-8000-000000000801', now(), true);

set local role authenticated;
select set_config('test.uid', '00000000-0000-4000-8000-000000000801', true);

do $$
declare
  first_id uuid := gen_random_uuid();
  second_id uuid := gen_random_uuid();
  first_visit date := (now() at time zone 'Asia/Manila')::date + 2;
  recorded_name text := E'  fixture Mara\t  VILLANUEVA  ';
  args text[] := array['guest-fixture'];
  created jsonb;
  result jsonb;
  booking_id uuid;
  completion_id uuid;
  quote_booking jsonb;
  preview jsonb;
begin
  created := public.herco_create_staff_guest_booking(first_id, first_visit, 8::smallint,
    args, 'New bike', recorded_name);
  booking_id := (created->>'id')::uuid;
  if booking_id is null or created->>'status' <> 'pending' or (created->>'totalCentavos')::integer <> 9000 then
    raise exception 'Guest booking was not saved with the expected price and status: %', created;
  end if;
  perform set_config('test.guest_booking_id', booking_id::text, true);

  result := public.herco_create_staff_guest_booking(first_id, first_visit, 8::smallint,
    args, 'New bike', recorded_name, null);
  if result is distinct from created then raise exception 'Guest retry returned a different booking'; end if;
  begin
    perform public.herco_create_staff_guest_booking(first_id, first_visit, 8::smallint,
      args, 'New bike', 'Changed name');
    raise exception 'Accepted modified retry';
  exception when invalid_parameter_value then null;
  end;

  begin
    perform public.herco_create_staff_guest_booking(second_id, first_visit + 1, 8::smallint,
      args, 'Other bike', 'Fixture Mara Villanuevas', '09170000001',
      expected_price_fingerprint => 'stale');
    raise exception 'Accepted stale price';
  exception when sqlstate 'P0409' then null;
  end;
  result := public.herco_create_staff_guest_booking(second_id, first_visit + 1, 8::smallint,
    args, 'Other bike', 'Fixture Mara Villanuevas', '09170000001');
  completion_id := (result->>'id')::uuid;
  perform set_config('test.guest_completion_id', completion_id::text, true);
  perform public.herco_confirm_booking(completion_id);

  preview := public.herco_preview_coating_price('Quoted bike', array['guest-fixture', 'guest-quote']);
  quote_booking := public.herco_create_staff_guest_booking(gen_random_uuid(), first_visit, 8::smallint,
    array['guest-fixture', 'guest-quote'], 'Quoted bike', 'Fixture guest quote',
    expected_price_fingerprint => preview->>'fingerprint');
  if quote_booking->'estimateOpen' is distinct from 'true'::jsonb
    or quote_booking->'totalCentavos' is distinct from preview->'totalCentavos' then
    raise exception 'Promoted fixed plus quote-only pricing does not match the preview';
  end if;

  begin
    perform public.herco_create_staff_guest_booking(gen_random_uuid(), first_visit + 2, 8::smallint,
      args, 'Blocked bike', 'Fixture blocked');
    raise exception 'Accepted blocked booking slot';
  exception when exclusion_violation then null;
  end;
  begin
    perform public.herco_create_staff_guest_booking(gen_random_uuid(), first_visit, 8::smallint,
      args, 'Missing name bike', E'\t ');
    raise exception 'Accepted blank guest name';
  exception when invalid_parameter_value then null;
  end;
  begin
    perform public.herco_create_staff_guest_booking(gen_random_uuid(), first_visit, 8::smallint,
      args, 'Short phone bike', 'Fixture short phone', '12');
    raise exception 'Accepted invalid phone';
  exception when invalid_parameter_value then null;
  end;

  result := public.herco_staff_booking_name_groups('customers', E' fixture\t MARA ');
  if (result->>'total')::integer <> 2 or (result#>>'{groups,0,total}')::integer <> 2
    or result#>>'{groups,0,name}' is distinct from recorded_name then
    raise exception 'Search or normalized distinct grouping failed: %', result;
  end if;
  result := public.herco_staff_booking_name_groups('history', p_name => 'FIXTURE   MARA VILLANUEVA');
  if (result->>'total')::integer <> 2 or result#>>'{bookings,0,id}' is distinct from booking_id::text
    or result#>>'{bookings,1,bike}' is distinct from 'Existing bike'
    or result::text like '%guest-customer@example.test%' then
    raise exception 'Group detail order, scope or privacy is wrong: %', result;
  end if;
  result := public.herco_staff_booking_name_groups('history', p_page => 2, p_name => recorded_name);
  if (result->>'total')::integer <> 2 or result->'bookings' <> '[]'::jsonb then
    raise exception 'Group page lost the full count: %', result;
  end if;

  result := public.herco_walk_in_intake((
    public.herco_staff_booking_name_groups('history', p_name => recorded_name)#>>'{bookings,1,id}'
  )::uuid);
  if result->>'state' is distinct from 'awaiting_request' or result->'canRequest' is distinct from 'true'::jsonb then
    raise exception 'Verified appointment intake request became unavailable: %', result;
  end if;

  result := public.herco_walk_in_intake(booking_id);
  if result->>'state' is distinct from 'unavailable' or result->'canRequest' is distinct from 'false'::jsonb
    or result->'canSign' is distinct from 'false'::jsonb or result->'form' is distinct from 'null'::jsonb then
    raise exception 'Guest intake is advertised as actionable: %', result;
  end if;
  begin
    perform public.herco_request_walk_in_intake(booking_id, 'invalid-guest-form');
    raise exception 'Guest intake was created';
  exception when insufficient_privilege then null;
  end;

  perform public.herco_confirm_booking(booking_id);
  perform public.herco_staff_change_booking(booking_id, gen_random_uuid(), 'reschedule',
    first_visit, 8::smallint, target_date => first_visit + 1, target_hour => 9::smallint);
  perform public.herco_staff_change_booking(booking_id, gen_random_uuid(), 'cancel',
    first_visit + 1, 9::smallint);
end
$$;

reset role;
insert into storage.objects (bucket_id, name)
values ('herco-completion', current_setting('test.guest_completion_id')
  || '/00000000-0000-4000-8000-000000000801/00000000-0000-4000-8000-000000000810.jpg');
set local role authenticated;
do $$
declare
  guest_id uuid := current_setting('test.guest_completion_id')::uuid;
  path text := guest_id::text || '/00000000-0000-4000-8000-000000000801/00000000-0000-4000-8000-000000000810.jpg';
begin
  if public.herco_complete_booking(guest_id, 9000, array[path], '') is null then
    raise exception 'Staff could not complete the ownerless booking';
  end if;
end $$;

select set_config('test.uid', '00000000-0000-4000-8000-000000000802', true);
do $$ begin
  perform public.herco_staff_booking_name_groups('history', p_name => 'Fixture Mara Villanueva');
  begin
    perform public.herco_staff_booking_name_groups('customers');
    raise exception 'Booking-history-only staff opened Customers groups';
  exception when insufficient_privilege then null;
  end;
end $$;

select set_config('test.uid', '00000000-0000-4000-8000-000000000804', true);
do $$ begin
  perform public.herco_staff_booking_name_groups('customers', p_name => 'Fixture Mara Villanueva');
  begin
    perform public.herco_staff_booking_name_groups('history', p_name => 'Fixture Mara Villanueva');
    raise exception 'Customers-only staff opened Booking History groups';
  exception when insufficient_privilege then null;
  end;
end $$;

select set_config('test.uid', '00000000-0000-4000-8000-000000000805', true);
do $$ begin
  begin
    perform public.herco_create_staff_guest_booking(gen_random_uuid(), current_date + 2, 9::smallint,
      array['guest-fixture'], 'Fixture bike', 'Fixture name');
    raise exception 'Staff without createBooking grant created a guest';
  exception when insufficient_privilege then null;
  end;
end $$;

select set_config('test.uid', '00000000-0000-4000-8000-000000000803', true);
do $$ begin
  if exists (select 1 from public.herco_bookings where id = current_setting('test.guest_booking_id')::uuid)
    or exists (select 1 from public.herco_booking_events where booking_id = current_setting('test.guest_booking_id')::uuid) then
    raise exception 'Same-name customer can access guest booking';
  end if;
  if not exists (select 1 from public.herco_bookings where customer_id = auth.uid()) then
    raise exception 'Customer lost access to their account booking';
  end if;
  begin
    perform public.herco_staff_booking_name_groups('history');
    raise exception 'Customer opened staff groups';
  exception when insufficient_privilege then null;
  end;
end $$;

-- The existing signed walk-in still belongs to the verified account and holds no appointment hour.
do $$
declare
  result jsonb;
  saved public.herco_bookings;
begin
  result := public.herco_create_walk_in_booking(gen_random_uuid(), (now() at time zone 'Asia/Manila')::date,
    array['guest-fixture'], 'Signed walk-in bike', 'Fixture signed customer', '09170000009',
    '', 'guest-regression-test', 'Fixture signed customer', true);
  select * into strict saved from public.herco_bookings where id = (result->>'id')::uuid;
  if saved.customer_id is distinct from auth.uid() or saved.visit_hour is not null
    or saved.booking_kind <> 'walk_in' or public.herco_walk_in_intake(saved.id)->>'state' is distinct from 'signed' then
    raise exception 'The verified walk-in signature or no-slot workflow changed';
  end if;
end $$;

reset role;
do $$
declare
  guest_id uuid := current_setting('test.guest_booking_id')::uuid;
  booking public.herco_bookings;
begin
  select * into strict booking from public.herco_bookings where id = guest_id;
  if booking.customer_id is not null or booking.customer_contact ? 'email' or booking.customer_contact->>'phone' <> ''
    or booking.customer_contact->>'name' is distinct from E'  fixture Mara\t  VILLANUEVA  ' or booking.status <> 'cancelled' then
    raise exception 'Guest ownership, original contact, or staff workflow is incorrect';
  end if;
  if (select count(*) from public.herco_booking_events where booking_id = guest_id) <> 4
    or exists (
      select 1 from herco_private.notification_outbox o
      join public.herco_booking_events e on e.id = o.event_id where e.booking_id in (guest_id, current_setting('test.guest_completion_id')::uuid)
    ) then
    raise exception 'Guest events should exist without outbox jobs';
  end if;
end $$;

rollback;
