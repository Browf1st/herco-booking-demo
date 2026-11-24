-- Staff Customers directory and details (migration 202611240002). Run against a fresh local or CI database
-- after every migration. Fictional data only; everything is rolled back.
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
  ('00000000-0000-4000-8000-000000000701','cd-owner@example.test',now()),
  ('00000000-0000-4000-8000-000000000702','cd-nogrant@example.test',now()),
  ('00000000-0000-4000-8000-000000000703','cd-booked@example.test',now()),
  ('00000000-0000-4000-8000-000000000704','cd-nobookings@example.test',now()),
  ('00000000-0000-4000-8000-000000000705','cd-unconfirmed@example.test',null);
insert into herco_private.staff_memberships(user_id,role,page_grants,action_grants,display_name) values
  ('00000000-0000-4000-8000-000000000701','owner',array['Customers'],array[]::text[],'Directory Owner'),
  ('00000000-0000-4000-8000-000000000702','staff',array['Bookings'],array[]::text[],'No Customers Page');
insert into public.herco_bookings(id,customer_id,request_id,request_payload,visit_date,visit_hour,bike,customer_contact,status,original_services,original_total_centavos) values
  ('00000000-0000-4000-8000-0000000007a1','00000000-0000-4000-8000-000000000703',gen_random_uuid(),'{}',current_date+90,10,'CD BIKE',
    '{"name":"Booked Fixture","phone":"+639170000701"}','pending','[{"code":"wash","label":"Wash","price_centavos":50000}]',50000);
-- 21 more customers (no bookings) to prove paging: 20 per page, then the last one.
insert into auth.users(id,email,email_confirmed_at)
  select ('00000000-0000-4000-8000-0000000007'||lpad((10+n)::text,2,'0'))::uuid,'cd-page'||n||'@example.test',now() from generate_series(1,21) n;

-- 0. Both functions are VOLATILE. PostgREST runs STABLE functions in a read-only transaction, where the
--    SELECT ... FOR SHARE in require_customers_page() fails with 25006. Signatures and grants are unchanged.
do $$ begin
  if (select count(*) from pg_proc where oid in ('public.herco_staff_customer_directory(text,uuid)'::regprocedure,
        'public.herco_staff_customer_details(uuid,integer)'::regprocedure) and provolatile='v' and prosecdef) <> 2 then
    raise exception 'Customer directory functions must be VOLATILE security definer'; end if;
  if has_function_privilege('anon','public.herco_staff_customer_directory(text,uuid)','execute')
    or has_function_privilege('anon','public.herco_staff_customer_details(uuid,integer)','execute')
    or not has_function_privilege('authenticated','public.herco_staff_customer_directory(text,uuid)','execute')
    or not has_function_privilege('authenticated','public.herco_staff_customer_details(uuid,integer)','execute') then
    raise exception 'Customer directory grants changed'; end if;
end $$;

-- 1. Staff with the Customers page: a customer with no bookings is listed (null name, phone, bike) and counted;
--    a customer with bookings keeps their details; staff and unconfirmed accounts are not listed.
set local role authenticated;
select set_config('test.uid','00000000-0000-4000-8000-000000000701',true);
do $$
declare r jsonb := public.herco_staff_customer_directory('cd-');
  expected bigint;
begin
  if not exists (select 1 from jsonb_array_elements(r->'customers') c where c->>'id'='00000000-0000-4000-8000-000000000704'
      and c->'name'='null'::jsonb and c->'phone'='null'::jsonb and c->'bike'='null'::jsonb and (c->>'booking_count')::int=0)
    then raise exception 'Customer with no bookings missing: %', r; end if;
  if not exists (select 1 from jsonb_array_elements(r->'customers') c where c->>'id'='00000000-0000-4000-8000-000000000703'
      and c->>'name'='Booked Fixture' and c->>'phone'='+639170000701' and c->>'bike'='CD BIKE' and (c->>'booking_count')::int=1)
    then raise exception 'Customer with a booking lost details: %', r; end if;
  if r::text like '%cd-owner@%' or r::text like '%cd-nogrant@%' then raise exception 'A staff account was listed: %', r; end if;
  if r::text like '%cd-unconfirmed@%' then raise exception 'An unconfirmed account was listed: %', r; end if;
  -- total: confirmed, non-staff accounts: 703, 704 and the 21 page fixtures
  if (r->>'total')::bigint <> 23 then raise exception 'Total should be 23, got %', r->>'total'; end if;
end $$;

-- 2. Search by email, and by name or phone of the latest booking.
do $$ begin
  if jsonb_array_length(public.herco_staff_customer_directory('NOBOOKINGS')->'customers') <> 1
    or jsonb_array_length(public.herco_staff_customer_directory('booked fixture')->'customers') <> 1
    or jsonb_array_length(public.herco_staff_customer_directory('9170000701')->'customers') <> 1
    or jsonb_array_length(public.herco_staff_customer_directory('cd-owner')->'customers') <> 0 then
    raise exception 'Search by email, name or phone failed (staff must never match)'; end if;
end $$;

-- 3. Paging: 20 per page ordered by id, the cursor continues after the last id of the page.
do $$
declare p1 jsonb := public.herco_staff_customer_directory('cd-page');
  p2 jsonb;
begin
  if jsonb_array_length(p1->'customers') <> 20 or p1->>'nextCursor' is null
    or p1->'customers'->19->>'id' <> p1->>'nextCursor' then raise exception 'Page 1 wrong: %', p1; end if;
  p2 := public.herco_staff_customer_directory('cd-page',(p1->>'nextCursor')::uuid);
  if jsonb_array_length(p2->'customers') <> 1 or p2->>'nextCursor' is not null
    or p2->'customers'->0->>'id' <= p1->>'nextCursor' then raise exception 'Page 2 wrong: %', p2; end if;
end $$;

-- 4. Details still work, including for a customer with no visits.
do $$
declare d jsonb := public.herco_staff_customer_details('00000000-0000-4000-8000-000000000703',1);
  e jsonb := public.herco_staff_customer_details('00000000-0000-4000-8000-000000000704',1);
begin
  if jsonb_array_length(d->'visits') <> 1 or (d->>'hasMore')::boolean then raise exception 'Details wrong: %', d; end if;
  if jsonb_array_length(e->'visits') <> 0 then raise exception 'Empty visits wrong: %', e; end if;
end $$;
select public.herco_test_refused($s$select public.herco_staff_customer_details('00000000-0000-4000-8000-000000000703',0)$s$,'22023');
select public.herco_test_refused($s$select public.herco_staff_customer_directory(repeat('x',255))$s$,'22023');

-- 5. Refused: staff without the Customers page, a customer account and a signed-out caller (all 42501).
select set_config('test.uid','00000000-0000-4000-8000-000000000702',true);
select public.herco_test_refused($s$select public.herco_staff_customer_directory('')$s$,'42501');
select public.herco_test_refused($s$select public.herco_staff_customer_details('00000000-0000-4000-8000-000000000703',1)$s$,'42501');
select set_config('test.uid','00000000-0000-4000-8000-000000000703',true);
select public.herco_test_refused($s$select public.herco_staff_customer_directory('')$s$,'42501');
select public.herco_test_refused($s$select public.herco_staff_customer_details('00000000-0000-4000-8000-000000000703',1)$s$,'42501');
select set_config('test.uid','',true);
select public.herco_test_refused($s$select public.herco_staff_customer_directory('')$s$,'42501');
reset role;
set local role anon;
select public.herco_test_refused($s$select public.herco_staff_customer_directory('')$s$,'42501');
reset role;

-- 6. A disabled staff member loses access at once.
update herco_private.staff_memberships set enabled=false where user_id='00000000-0000-4000-8000-000000000701';
set local role authenticated;
select set_config('test.uid','00000000-0000-4000-8000-000000000701',true);
select public.herco_test_refused($s$select public.herco_staff_customer_directory('')$s$,'42501');
reset role;

rollback;
