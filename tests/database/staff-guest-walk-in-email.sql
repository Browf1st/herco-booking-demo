-- Fictional records only. Run after migrations against a local test database.
begin;

insert into auth.users (id, email, email_confirmed_at) values
  ('00000000-0000-4000-8000-000000000901', 'walkin-staff@example.test', now()),
  ('00000000-0000-4000-8000-000000000902', 'walkin-no-create@example.test', now());

insert into herco_private.staff_memberships (user_id, role, page_grants, action_grants) values
  ('00000000-0000-4000-8000-000000000901', 'owner', array['Bookings'], array['createBooking','confirmBooking','completeBooking']),
  ('00000000-0000-4000-8000-000000000902', 'staff', array['Bookings'], array[]::text[]);

insert into herco_private.services (code, label, price_centavos, enabled)
values ('walkin-fixture', 'Walk-in fixture service', 10000, true);

set local role authenticated;
select set_config('test.uid', '00000000-0000-4000-8000-000000000901', true);

do $$
declare
  today date := (now() at time zone 'Asia/Manila')::date;
  first_id uuid := gen_random_uuid();
  second_id uuid := gen_random_uuid();
  created jsonb;
  again jsonb;
  saved public.herco_bookings;
begin
  -- Name only: no phone, no email, no hour, no intake.
  created := public.herco_create_staff_guest_booking(first_id, today, null, array['walkin-fixture'],
    'Walk-in bike', 'Fixture walk-in guest', walk_in => true);
  select * into strict saved from public.herco_bookings where id = (created->>'id')::uuid;
  if saved.customer_id is not null or saved.guest_staff_actor_id <> auth.uid() or saved.booking_kind <> 'walk_in'
    or saved.visit_hour is not null or saved.visit_date <> today or saved.status <> 'confirmed'
    or saved.customer_contact->>'email' <> '' or saved.customer_contact->>'phone' <> ''
    or created->>'intakeRequired' <> 'false' then
    raise exception 'Guest walk-in was not saved as a direct same-day walk-in: %', saved;
  end if;
  if exists (select 1 from herco_private.walk_in_intakes where booking_id = saved.id) then
    raise exception 'Guest walk-in must not create an intake';
  end if;

  -- Retrying the same request returns the same booking.
  again := public.herco_create_staff_guest_booking(first_id, today, null, array['walkin-fixture'],
    'Walk-in bike', 'Fixture walk-in guest', walk_in => true);
  if again->>'id' <> created->>'id' then raise exception 'Retry created a second booking'; end if;

  -- Omitting the date books for today in Manila.
  created := public.herco_create_staff_guest_booking(gen_random_uuid(), null, null, array['walkin-fixture'],
    'Walk-in bike', 'Fixture walk-in guest', walk_in => true);
  if (select visit_date from public.herco_bookings where id = (created->>'id')::uuid) <> today then
    raise exception 'Undated guest walk-in was not booked for today';
  end if;

  -- Email is stored trimmed when given.
  created := public.herco_create_staff_guest_booking(second_id, today, null, array['walkin-fixture'],
    'Walk-in bike', 'Fixture walk-in guest', walk_in => true, customer_email => '  guest@example.test ');
  select * into strict saved from public.herco_bookings where id = (created->>'id')::uuid;
  if saved.customer_contact->>'email' is distinct from 'guest@example.test' then
    raise exception 'Guest email was not stored: %', saved.customer_contact;
  end if;

  -- A walk-in must be today, with no reserved hour and a valid email.
  begin
    perform public.herco_create_staff_guest_booking(gen_random_uuid(), today, 9::smallint, array['walkin-fixture'],
      'Walk-in bike', 'Fixture walk-in guest', walk_in => true);
    raise exception 'Walk-in accepted a reserved hour';
  exception when invalid_parameter_value then null;
  end;
  begin
    perform public.herco_create_staff_guest_booking(gen_random_uuid(), today + 1, null, array['walkin-fixture'],
      'Walk-in bike', 'Fixture walk-in guest', walk_in => true);
    raise exception 'Walk-in accepted another day';
  exception when invalid_parameter_value then null;
  end;
  begin
    perform public.herco_create_staff_guest_booking(gen_random_uuid(), today, null, array['walkin-fixture'],
      'Walk-in bike', 'Fixture walk-in guest', walk_in => true, customer_email => 'not an email');
    raise exception 'Invalid email accepted';
  exception when invalid_parameter_value then null;
  end;
end $$;

select set_config('test.uid', '00000000-0000-4000-8000-000000000902', true);
do $$ begin
  begin
    perform public.herco_create_staff_guest_booking(gen_random_uuid(), (now() at time zone 'Asia/Manila')::date, null,
      array['walkin-fixture'], 'Walk-in bike', 'Fixture walk-in guest', walk_in => true);
    raise exception 'Staff without createBooking grant created a guest walk-in';
  exception when insufficient_privilege then null;
  end;
end $$;

rollback;
