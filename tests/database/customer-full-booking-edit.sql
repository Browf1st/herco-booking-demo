-- Customer edits a whole pending booking (migration 202611280006). Fictional data only; everything is rolled back.
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

insert into auth.users(id,email,email_confirmed_at) values
  ('00000000-0000-4000-8000-000000000801','fe-owner@example.test',now()),
  ('00000000-0000-4000-8000-000000000802','fe-other@example.test',now());

-- A: pending. B: confirmed. Both belong to customer 801.
insert into public.herco_bookings(id,customer_id,request_id,request_payload,visit_date,visit_hour,bike,customer_contact,status,original_services,original_total_centavos,created_at) values
  ('00000000-0000-4000-8000-0000000008a1','00000000-0000-4000-8000-000000000801',gen_random_uuid(),'{}',current_date+60,10,'FE BIKE ONE',
   '{"name":"Fixture Customer","email":"fe-owner@example.test","phone":"+639170002222","plate":"AAA111"}','pending',
   '[{"code":"wash","label":"Wash","price_centavos":50000}]',50000,now()),
  ('00000000-0000-4000-8000-0000000008a2','00000000-0000-4000-8000-000000000801',gen_random_uuid(),'{}',current_date+61,10,'FE BIKE TWO',
   '{"name":"Fixture Customer","email":"fe-owner@example.test","phone":"+639170002222","plate":"BBB222"}','confirmed',
   '[{"code":"wash","label":"Wash","price_centavos":50000}]',50000,now());

-- Allowed actor: the owner edits their own pending booking.
set local role authenticated;
select set_config('test.uid','00000000-0000-4000-8000-000000000801',true);
do $$
declare r jsonb; b public.herco_bookings;
begin
  r := public.herco_edit_booking_configured('00000000-0000-4000-8000-0000000008a1',gen_random_uuid(),0,'  FE BIKE NEW  ','  New Name ','','NEW 123',array['wash'],'{}'::jsonb);
  if r->>'bike' <> 'FE BIKE NEW' or r->'contact' <> '{"name":"New Name","phone":"","plate":"NEW 123"}'::jsonb then raise exception 'Bike or contact not saved: %', r; end if;
  if r::text like '%fe-owner@example.test%' then raise exception 'Email leaked: %', r; end if;
  if (r->>'revision')::int <> 1 then raise exception 'Revision should be 1: %', r; end if;
  select * into b from public.herco_bookings where id='00000000-0000-4000-8000-0000000008a1';
  if b.customer_contact->>'email' <> 'fe-owner@example.test' then raise exception 'Email must stay: %', b.customer_contact; end if;
  if b.original_total_centavos <> 50000 or b.original_services <> '[{"code":"wash","label":"Wash","price_centavos":50000}]'::jsonb then raise exception 'Original snapshot changed'; end if;
  -- No change: the revision does not move.
  r := public.herco_edit_booking_configured('00000000-0000-4000-8000-0000000008a1',gen_random_uuid(),1,'FE BIKE NEW','New Name','','NEW 123',array['wash'],'{}'::jsonb);
  if (r->>'revision')::int <> 1 then raise exception 'No-op must not bump revision: %', r; end if;
end $$;
-- Bad input and stale revision.
select public.herco_test_refused($s$select public.herco_edit_booking_configured('00000000-0000-4000-8000-0000000008a1',gen_random_uuid(),1,'   ','Name','','',array['wash'],'{}'::jsonb)$s$,'22023');
select public.herco_test_refused($s$select public.herco_edit_booking_configured('00000000-0000-4000-8000-0000000008a1',gen_random_uuid(),1,'Bike','','','',array['wash'],'{}'::jsonb)$s$,'22023');
select public.herco_test_refused($s$select public.herco_edit_booking_configured('00000000-0000-4000-8000-0000000008a1',gen_random_uuid(),1,'Bike','Name','12','',array['wash'],'{}'::jsonb)$s$,'22023');
select public.herco_test_refused($s$select public.herco_edit_booking_configured('00000000-0000-4000-8000-0000000008a1',gen_random_uuid(),0,'Bike','Name','','',array['wash'],'{}'::jsonb)$s$,'40001');
-- A confirmed booking is not editable by the customer.
select public.herco_test_refused($s$select public.herco_edit_booking_configured('00000000-0000-4000-8000-0000000008a2',gen_random_uuid(),0,'Bike','Name','','',array['wash'],'{}'::jsonb)$s$,'40001');
reset role;

-- Denied actor: a different signed-in user.
set local role authenticated;
select set_config('test.uid','00000000-0000-4000-8000-000000000802',true);
select public.herco_test_refused($s$select public.herco_edit_booking_configured('00000000-0000-4000-8000-0000000008a1',gen_random_uuid(),1,'Hacked','Hacker','','',array['wash'],'{}'::jsonb)$s$,'42501');
select public.herco_test_refused($s$select public.herco_booked_services('00000000-0000-4000-8000-0000000008a1')$s$,'42501');
reset role;

-- Not signed in.
set local role anon;
select public.herco_test_refused($s$select public.herco_edit_booking_configured('00000000-0000-4000-8000-0000000008a1',gen_random_uuid(),1,'Bike','Name','','',array['wash'],'{}'::jsonb)$s$,'42501');
reset role;

rollback;
