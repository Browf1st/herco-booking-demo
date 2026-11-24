-- F-007 staff price changes + F-011 history and sorts. Run against a fresh local or CI database after every migration.
-- Fictional data only; everything is rolled back.
begin;

-- Helper (rolled back with the rest): runs a statement and expects one SQLSTATE.
create function public.herco_test_refused(statement text, state text) returns void language plpgsql as $$
begin
  execute statement;
  raise exception 'NOT REFUSED: %', statement;
exception when others then
  if sqlstate is distinct from state then
    raise exception 'Expected % but got % (%) for: %', state, sqlstate, sqlerrm, statement;
  end if;
end $$;
-- Helper: fixture ids (last hex digit) of a records result, as text like "1,2,3".
create function public.herco_test_order(result jsonb) returns text language sql immutable as $$
  select string_agg(right(r->>'id',1),',' order by n) from jsonb_array_elements(result->'records') with ordinality t(r,n)
$$;
-- Helper: kinds of a history result, newest first, like "price_changed,booked".
create function public.herco_test_kinds(result jsonb) returns text language sql immutable as $$
  select string_agg(e->>'kind',',' order by n) from jsonb_array_elements(result->'entries') with ordinality t(e,n)
$$;

insert into auth.users(id,email,email_confirmed_at) values
  ('00000000-0000-4000-8000-000000000601','pe-owner@example.test',now()),
  ('00000000-0000-4000-8000-000000000602','pe-admin@example.test',now()),
  ('00000000-0000-4000-8000-000000000603','pe-staff@example.test',now()),
  ('00000000-0000-4000-8000-000000000604','pe-customer@example.test',now());
insert into herco_private.staff_memberships(user_id,role,page_grants,action_grants,display_name) values
  ('00000000-0000-4000-8000-000000000601','owner',array['Bookings','Reports'],array['viewIncome','adjustPrices','editServices'],'Admin Elijah'),
  ('00000000-0000-4000-8000-000000000602','admin',array['Bookings'],array['adjustPrices'],'Mia'),
  ('00000000-0000-4000-8000-000000000603','staff',array['Bookings'],array['editServices'],'Noel');

-- A: Pending, one service added earlier (helmet). B: Booked, quote-only line. C: Done. D: Cancelled.
insert into public.herco_bookings(id,customer_id,request_id,request_payload,visit_date,visit_hour,bike,customer_contact,status,original_services,original_total_centavos,created_at) values
  ('00000000-0000-4000-8000-0000000006a1','00000000-0000-4000-8000-000000000604',gen_random_uuid(),'{}',current_date+70,10,'PEDIT A',
    '{"name":"Fixture Customer","email":"secret-customer@example.test","phone":"+639170000000"}','pending',
    '[{"code":"ceramic","label":"Ceramic coating","price_centavos":179900},{"code":"wash","label":"Wash","price_centavos":50000}]',229900,now()-interval '6 days'),
  ('00000000-0000-4000-8000-0000000006a2','00000000-0000-4000-8000-000000000604',gen_random_uuid(),'{}',current_date+71,10,'PEDIT B','{}','confirmed',
    '[{"code":"repair","label":"Frame repair","max_centavos":500000,"quote_required":true}]',0,now()),
  ('00000000-0000-4000-8000-0000000006a3','00000000-0000-4000-8000-000000000604',gen_random_uuid(),'{}',current_date+72,10,'PEDIT C','{}','done',
    '[{"code":"ceramic","label":"Ceramic coating","price_centavos":179900}]',179900,now()),
  ('00000000-0000-4000-8000-0000000006a4','00000000-0000-4000-8000-000000000604',gen_random_uuid(),'{}',current_date+73,10,'PEDIT D','{}','cancelled',
    '[{"code":"wash","label":"Wash","price_centavos":50000}]',50000,now());

-- A earlier staff service change (revision 1): helmet added at today's catalog price.
update public.herco_bookings set current_services='[{"code":"ceramic","label":"Ceramic coating","price_centavos":179900},{"code":"wash","label":"Wash","price_centavos":50000},{"code":"helmet","label":"Helmet coating","price_centavos":29900}]',
  current_total_centavos=259800, service_revision=1 where id='00000000-0000-4000-8000-0000000006a1';
insert into herco_private.booking_service_changes(booking_id,actor_id,request_id,revision,service_codes,before_services,after_services,recorded_at) values
  ('00000000-0000-4000-8000-0000000006a1','00000000-0000-4000-8000-000000000601',gen_random_uuid(),1,array['ceramic','helmet','wash'],
    '[{"code":"ceramic","label":"Ceramic coating","price_centavos":179900},{"code":"wash","label":"Wash","price_centavos":50000}]',
    '[{"code":"ceramic","label":"Ceramic coating","price_centavos":179900},{"code":"wash","label":"Wash","price_centavos":50000},{"code":"helmet","label":"Helmet coating","price_centavos":29900}]',
    now()-interval '3 days');
-- Status events with times in the past.
insert into public.herco_booking_events(booking_id,actor_id,kind,to_status,created_at) values
  ('00000000-0000-4000-8000-0000000006a1','00000000-0000-4000-8000-000000000604','booking_submitted','pending',now()-interval '6 days'),
  ('00000000-0000-4000-8000-0000000006a1','00000000-0000-4000-8000-000000000601','booking_confirmed','confirmed',now()-interval '5 days'),
  ('00000000-0000-4000-8000-0000000006a3','00000000-0000-4000-8000-000000000604','booking_submitted','pending',now()-interval '10 days'),
  ('00000000-0000-4000-8000-0000000006a3','00000000-0000-4000-8000-000000000601','booking_confirmed','confirmed',now()-interval '9 days'),
  ('00000000-0000-4000-8000-0000000006a3','00000000-0000-4000-8000-000000000601','completed','done',now()-interval '8 days'),
  ('00000000-0000-4000-8000-0000000006a4','00000000-0000-4000-8000-000000000604','booking_submitted','pending',now()-interval '4 days'),
  ('00000000-0000-4000-8000-0000000006a4','00000000-0000-4000-8000-000000000601','booking_rescheduled_by_staff','pending',now()-interval '3 days'),
  ('00000000-0000-4000-8000-0000000006a4','00000000-0000-4000-8000-000000000601','booking_services_updated','pending',now()-interval '2 days'),
  ('00000000-0000-4000-8000-0000000006a4','00000000-0000-4000-8000-000000000601','booking_cancelled_by_staff','cancelled',now()-interval '1 days');
-- C: a post-Done price correction (migration 0023 table).
insert into herco_private.booking_completion(booking_id,actor_id,final_price_centavos,photo_paths,note) values
  ('00000000-0000-4000-8000-0000000006a3','00000000-0000-4000-8000-000000000601',179900,array['00000000-0000-4000-8000-0000000006a3/fixture/a.jpg'],'Private fixture note');
insert into herco_private.booking_price_corrections(booking_id,revision,actor_id,request_id,service_code,previous_centavos,corrected_centavos,
  previous_completed_centavos,corrected_completed_centavos,reason,recorded_at) values
  ('00000000-0000-4000-8000-0000000006a3',1,'00000000-0000-4000-8000-000000000602',gen_random_uuid(),'ceramic',179900,200000,179900,200000,'Final check',now()-interval '7 days');
update public.herco_bookings set current_services='[{"code":"ceramic","label":"Ceramic coating","price_centavos":200000}]',current_total_centavos=200000,service_revision=1
  where id='00000000-0000-4000-8000-0000000006a3';

-- 1. Happy path as the owner: change the ceramic line of A. Total is the sum of the current lines.
set local role authenticated;
select set_config('test.uid','00000000-0000-4000-8000-000000000601',true);
do $$
declare r jsonb;
begin
  r := public.herco_staff_set_line_price('00000000-0000-4000-8000-0000000006a1','00000000-0000-4000-8000-0000000006c1','ceramic',179900,230000,'  Extra corrosion found  ');
  if (r->>'revision')::int <> 2 then raise exception 'Revision should be 2: %', r; end if;
  if (r->>'totalCentavos')::bigint <> 230000+50000+29900 or r->>'status' <> 'pending' then raise exception 'Total not recomputed: %', r; end if;
  if (select (l->>'price_centavos')::bigint from jsonb_array_elements(r->'lines') l where l->>'code'='ceramic') <> 230000 then raise exception 'Line not changed: %', r; end if;
  if jsonb_array_length(r->'lines') <> 3 then raise exception 'Other lines lost: %', r; end if;
end $$;
reset role;
do $$
begin
  -- The original snapshot is untouched; the current lines and total changed together.
  if not exists (select 1 from public.herco_bookings where id='00000000-0000-4000-8000-0000000006a1' and original_total_centavos=229900
    and original_services='[{"code":"ceramic","label":"Ceramic coating","price_centavos":179900},{"code":"wash","label":"Wash","price_centavos":50000}]'::jsonb
    and current_total_centavos=309900 and service_revision=2) then raise exception 'Booking row wrong after price change'; end if;
  if not exists (select 1 from herco_private.booking_price_edits where booking_id='00000000-0000-4000-8000-0000000006a1' and revision=2
    and actor_id='00000000-0000-4000-8000-000000000601' and service_code='ceramic' and service_label='Ceramic coating'
    and previous_centavos=179900 and new_centavos=230000 and reason='Extra corrosion found') then raise exception 'History row missing'; end if;
  if not exists (select 1 from public.herco_booking_events where booking_id='00000000-0000-4000-8000-0000000006a1' and kind='booking_line_price_changed' and to_status='pending')
    then raise exception 'Activity event missing'; end if;
end $$;

-- 2. Retry with the same request id: same answer, nothing new written. Another value under the same id: refused.
set local role authenticated;
select set_config('test.uid','00000000-0000-4000-8000-000000000601',true);
select public.herco_staff_set_line_price('00000000-0000-4000-8000-0000000006a1','00000000-0000-4000-8000-0000000006c1','ceramic',179900,230000,'Extra corrosion found');
select public.herco_test_refused($s$select public.herco_staff_set_line_price('00000000-0000-4000-8000-0000000006a1','00000000-0000-4000-8000-0000000006c1','ceramic',179900,240000,'Extra corrosion found')$s$,'22023');
reset role;
do $$ begin
  if (select count(*) from herco_private.booking_price_edits where booking_id='00000000-0000-4000-8000-0000000006a1') <> 1
    or (select service_revision from public.herco_bookings where id='00000000-0000-4000-8000-0000000006a1') <> 2 then raise exception 'A retry wrote again'; end if;
end $$;

-- 3. Each refusal (as the owner). 22023 bad input, P0412 stale line, P0423 locked, P0002 missing.
set local role authenticated;
select set_config('test.uid','00000000-0000-4000-8000-000000000601',true);
-- stale: the ceramic line is now 230000, not 179900; an unknown service; a missing price when the line has one
select public.herco_test_refused($s$select public.herco_staff_set_line_price('00000000-0000-4000-8000-0000000006a1',gen_random_uuid(),'ceramic',179900,200000,'Stale')$s$,'P0412');
select public.herco_test_refused($s$select public.herco_staff_set_line_price('00000000-0000-4000-8000-0000000006a1',gen_random_uuid(),'ceramic',null,200000,'Stale')$s$,'P0412');
select public.herco_test_refused($s$select public.herco_staff_set_line_price('00000000-0000-4000-8000-0000000006a1',gen_random_uuid(),'nothing',null,200000,'Missing line')$s$,'P0412');
-- invalid values: negative, not whole pesos, above 1,000,000 pesos, same price, blank / long reason, bad ids
select public.herco_test_refused($s$select public.herco_staff_set_line_price('00000000-0000-4000-8000-0000000006a1',gen_random_uuid(),'wash',50000,-100,'Negative')$s$,'22023');
select public.herco_test_refused($s$select public.herco_staff_set_line_price('00000000-0000-4000-8000-0000000006a1',gen_random_uuid(),'wash',50000,150050,'Centavos')$s$,'22023');
select public.herco_test_refused($s$select public.herco_staff_set_line_price('00000000-0000-4000-8000-0000000006a1',gen_random_uuid(),'wash',50000,100000100,'Too high')$s$,'22023');
select public.herco_test_refused($s$select public.herco_staff_set_line_price('00000000-0000-4000-8000-0000000006a1',gen_random_uuid(),'wash',50000,50000,'Same price')$s$,'P0400');
select public.herco_test_refused($s$select public.herco_staff_set_line_price('00000000-0000-4000-8000-0000000006a1',gen_random_uuid(),'wash',50000,60000,'   ')$s$,'22023');
select public.herco_test_refused($s$select public.herco_staff_set_line_price('00000000-0000-4000-8000-0000000006a1',gen_random_uuid(),'wash',50000,60000,null)$s$,'22023');
select public.herco_test_refused($s$select public.herco_staff_set_line_price('00000000-0000-4000-8000-0000000006a1',gen_random_uuid(),'wash',50000,60000,repeat('x',201))$s$,'22023');
select public.herco_test_refused($s$select public.herco_staff_set_line_price('00000000-0000-4000-8000-0000000006a1',gen_random_uuid(),null,50000,60000,'No service')$s$,'22023');
select public.herco_test_refused($s$select public.herco_staff_set_line_price('00000000-0000-4000-8000-0000000006a1',null,'wash',50000,60000,'No request id')$s$,'22023');
select public.herco_test_refused($s$select public.herco_staff_set_line_price(null,gen_random_uuid(),'wash',50000,60000,'No booking')$s$,'22023');
select public.herco_test_refused($s$select public.herco_staff_set_line_price('00000000-0000-4000-8000-0000000006a1',gen_random_uuid(),'wash',-5,60000,'Bad expected')$s$,'22023');
-- locked: Done and Cancelled; unknown booking
select public.herco_test_refused($s$select public.herco_staff_set_line_price('00000000-0000-4000-8000-0000000006a3',gen_random_uuid(),'ceramic',200000,210000,'Done')$s$,'P0423');
select public.herco_test_refused($s$select public.herco_staff_set_line_price('00000000-0000-4000-8000-0000000006a4',gen_random_uuid(),'wash',50000,60000,'Cancelled')$s$,'P0423');
select public.herco_test_refused($s$select public.herco_staff_set_line_price(gen_random_uuid(),gen_random_uuid(),'wash',50000,60000,'Missing')$s$,'P0002');
reset role;
do $$ begin
  if (select count(*) from herco_private.booking_price_edits) <> 1 then raise exception 'A refused change was recorded'; end if;
  if (select current_total_centavos from public.herco_bookings where id='00000000-0000-4000-8000-0000000006a1') <> 309900 then raise exception 'A refused change moved the total'; end if;
end $$;

-- 4. A second staff member (no viewIncome) edits another line; limits 0 and 1,000,000 pesos are allowed.
set local role authenticated;
select set_config('test.uid','00000000-0000-4000-8000-000000000602',true);
do $$
declare r jsonb;
begin
  r := public.herco_staff_set_line_price('00000000-0000-4000-8000-0000000006a1','00000000-0000-4000-8000-0000000006c2','wash',50000,0,'Waived after inspection');
  if (r->>'totalCentavos')::bigint <> 230000+0+29900 or (r->>'revision')::int <> 3 then raise exception 'Free price failed: %', r; end if;
end $$;
select set_config('test.uid','00000000-0000-4000-8000-000000000601',true);
do $$
declare r jsonb;
begin
  r := public.herco_staff_set_line_price('00000000-0000-4000-8000-0000000006a1','00000000-0000-4000-8000-0000000006c3','wash',0,100000000,repeat('x',200));
  if (r->>'totalCentavos')::bigint <> 230000+100000000+29900 or (r->>'revision')::int <> 4 then raise exception 'Maximum price failed: %', r; end if;
end $$;

-- 5. A quote-only line (no exact price): expected null; the quote flags are cleared once a price is set.
do $$
declare r jsonb;
begin
  r := public.herco_staff_set_line_price('00000000-0000-4000-8000-0000000006a2','00000000-0000-4000-8000-0000000006c4','repair',null,150000,'Quote after inspection');
  if (r->>'totalCentavos')::bigint <> 150000 or r->>'status' <> 'confirmed' then raise exception 'Quote line failed: %', r; end if;
  if (r->'lines'->0) ? 'quote_required' or (r->'lines'->0) ? 'max_centavos' then raise exception 'Quote flags kept: %', r; end if;
end $$;
select public.herco_test_refused($s$select public.herco_staff_set_line_price('00000000-0000-4000-8000-0000000006a2',gen_random_uuid(),'repair',null,160000,'Stale')$s$,'P0412');
reset role;
do $$ begin
  if not exists (select 1 from public.herco_bookings where id='00000000-0000-4000-8000-0000000006a2' and original_total_centavos=0
    and original_services->0 ? 'quote_required') then raise exception 'Original quote snapshot changed'; end if;
end $$;
-- A repeat after the booking became Done is still answered (nothing new is written).
update public.herco_bookings set status='done' where id='00000000-0000-4000-8000-0000000006a2';
set local role authenticated;
select set_config('test.uid','00000000-0000-4000-8000-000000000601',true);
select public.herco_staff_set_line_price('00000000-0000-4000-8000-0000000006a2','00000000-0000-4000-8000-0000000006c4','repair',null,150000,'Quote after inspection');
select public.herco_test_refused($s$select public.herco_staff_set_line_price('00000000-0000-4000-8000-0000000006a2',gen_random_uuid(),'repair',150000,160000,'Late')$s$,'P0423');
reset role;
update public.herco_bookings set status='confirmed' where id='00000000-0000-4000-8000-0000000006a2';

-- 6. Who may do it: staff without adjustPrices, a customer (even the owner of the booking) and a signed-out caller.
set local role authenticated;
select set_config('test.uid','00000000-0000-4000-8000-000000000603',true);
select public.herco_test_refused($s$select public.herco_staff_set_line_price('00000000-0000-4000-8000-0000000006a1',gen_random_uuid(),'wash',100000000,50000,'No grant')$s$,'42501');
select set_config('test.uid','00000000-0000-4000-8000-000000000604',true);
select public.herco_test_refused($s$select public.herco_staff_set_line_price('00000000-0000-4000-8000-0000000006a1',gen_random_uuid(),'wash',100000000,50000,'Customer')$s$,'42501');
select public.herco_test_refused($s$select public.herco_booking_history('00000000-0000-4000-8000-0000000006a1')$s$,'42501');
-- The customer sees current and original totals on their own booking (what My Bookings shows).
do $$ begin
  if not exists (select 1 from public.herco_bookings where id='00000000-0000-4000-8000-0000000006a1' and current_total_centavos=100259900
    and original_total_centavos=229900 and jsonb_array_length(current_services)=3) then raise exception 'Customer cannot read current and original totals'; end if;
end $$;
reset role;
set local role anon;
select set_config('test.uid','',true);
select public.herco_test_refused($s$select public.herco_staff_set_line_price('00000000-0000-4000-8000-0000000006a1',gen_random_uuid(),'wash',100000000,50000,'Anon')$s$,'42501');
select public.herco_test_refused($s$select public.herco_booking_history('00000000-0000-4000-8000-0000000006a1')$s$,'42501');
reset role;

-- 7. History for A with viewIncome: newest first, merged from price changes, the added service and status events.
set local role authenticated;
select set_config('test.uid','00000000-0000-4000-8000-000000000601',true);
do $$
declare h jsonb := public.herco_booking_history('00000000-0000-4000-8000-0000000006a1');
  first_entry jsonb; added jsonb;
begin
  if public.herco_test_kinds(h) <> 'price_changed,price_changed,price_changed,service_added,approved,booked' then
    raise exception 'History order wrong: %', public.herco_test_kinds(h); end if;
  if not (h->>'canViewIncome')::boolean then raise exception 'canViewIncome should be true'; end if;
  first_entry := h->'entries'->0; added := h->'entries'->3;
  if first_entry->>'actor' <> 'Admin Elijah' or first_entry->>'service_code' <> 'wash' or (first_entry->>'from_centavos')::bigint <> 0
    or (first_entry->>'to_centavos')::bigint <> 100000000 or length(first_entry->>'reason') <> 200 then raise exception 'Newest entry wrong: %', first_entry; end if;
  if h->'entries'->1->>'actor' <> 'Mia' or h->'entries'->1->>'reason' <> 'Waived after inspection' then raise exception 'Second entry wrong: %', h->'entries'->1; end if;
  if h->'entries'->2->>'service_label' <> 'Ceramic coating' or (h->'entries'->2->>'from_centavos')::bigint <> 179900
    or (h->'entries'->2->>'to_centavos')::bigint <> 230000 then raise exception 'Ceramic entry wrong: %', h->'entries'->2; end if;
  if added->>'service_label' <> 'Helmet coating' or (added->>'to_centavos')::bigint <> 29900 or added->>'actor' <> 'Admin Elijah' then raise exception 'Added entry wrong: %', added; end if;
  if h->'entries'->4->>'actor' <> 'Admin Elijah' or h->'entries'->5->>'actor' <> 'Customer' then raise exception 'Status actors wrong: %', h; end if;
  -- no emails, phones or notes
  if h::text ~ '(secret-customer|@|\+63|Private fixture note)' then raise exception 'Private data leaked: %', h; end if;
end $$;
-- 7b. Done booking: the price correction after Done, then the status events. Cancelled booking: only status events, no noise kinds.
do $$
declare h jsonb := public.herco_booking_history('00000000-0000-4000-8000-0000000006a3');
begin
  if public.herco_test_kinds(h) <> 'price_corrected,completed,approved,booked' then raise exception 'Done history wrong: %', public.herco_test_kinds(h); end if;
  if h->'entries'->0->>'service_label' <> 'Ceramic coating' or h->'entries'->0->>'reason' <> 'Final check' or h->'entries'->0->>'actor' <> 'Mia'
    or (h->'entries'->0->>'to_centavos')::bigint <> 200000 then raise exception 'Correction entry wrong: %', h->'entries'->0; end if;
  h := public.herco_booking_history('00000000-0000-4000-8000-0000000006a4');
  if public.herco_test_kinds(h) <> 'cancelled,rescheduled,booked' then raise exception 'Cancelled history wrong: %', public.herco_test_kinds(h); end if;
end $$;
select public.herco_test_refused($s$select public.herco_booking_history(gen_random_uuid())$s$,'P0002');
select public.herco_test_refused($s$select public.herco_booking_history(null)$s$,'22023');

-- 8. Without viewIncome the history has no amounts at all (same entries).
select set_config('test.uid','00000000-0000-4000-8000-000000000602',true);
do $$
declare h jsonb := public.herco_booking_history('00000000-0000-4000-8000-0000000006a1');
begin
  if public.herco_test_kinds(h) <> 'price_changed,price_changed,price_changed,service_added,approved,booked' then raise exception 'Order changed without income: %', public.herco_test_kinds(h); end if;
  if (h->>'canViewIncome')::boolean then raise exception 'canViewIncome should be false'; end if;
  if h::text ~ 'centavos' then raise exception 'An amount leaked: %', h; end if;
  if h->'entries'->0->>'service_label' <> 'Wash' then raise exception 'Labels should remain'; end if;
  h := public.herco_booking_history('00000000-0000-4000-8000-0000000006a3');
  if h::text ~ 'centavos' then raise exception 'A correction amount leaked: %', h; end if;
end $$;
reset role;

-- 9. Reports sort and search. Fixtures: S1 pending 300000; S2 booked, estimate 400000 but edited to 120000; S3 done, final 50000; S4 done, no final price.
insert into public.herco_bookings(id,customer_id,request_id,request_payload,visit_date,visit_hour,bike,customer_contact,status,original_services,original_total_centavos,created_at) values
  ('00000000-0000-4000-8000-0000000006b1','00000000-0000-4000-8000-000000000604',gen_random_uuid(),'{}',current_date+80,10,'PSORT 1','{"name":"Zed Fixture","phone":"+639171110000","email":"zed@example.test"}','pending','[{"code":"a","label":"Wash","price_centavos":300000}]',300000,now()-interval '4 hours'),
  ('00000000-0000-4000-8000-0000000006b2','00000000-0000-4000-8000-000000000604',gen_random_uuid(),'{}',current_date+81,10,'PSORT 2','{}','confirmed','[{"code":"a","label":"Wash","price_centavos":400000}]',400000,now()-interval '3 hours'),
  ('00000000-0000-4000-8000-0000000006b3','00000000-0000-4000-8000-000000000604',gen_random_uuid(),'{}',current_date+82,10,'PSORT 3','{}','done','[{"code":"a","label":"Wash","price_centavos":900000}]',900000,now()-interval '2 hours'),
  ('00000000-0000-4000-8000-0000000006b4','00000000-0000-4000-8000-000000000604',gen_random_uuid(),'{}',current_date+83,10,'PSORT 4','{}','done','[{"code":"a","label":"Wash","price_centavos":10000}]',10000,now()-interval '1 hours');
update public.herco_bookings set current_services='[{"code":"a","label":"Wash","price_centavos":120000}]',current_total_centavos=120000
  where id='00000000-0000-4000-8000-0000000006b2';
insert into herco_private.booking_completion(booking_id,actor_id,final_price_centavos,photo_paths,note) values
  ('00000000-0000-4000-8000-0000000006b3','00000000-0000-4000-8000-000000000601',50000,array['00000000-0000-4000-8000-0000000006b3/fixture/a.jpg'],'Fixture note');
set local role authenticated;
select set_config('test.uid','00000000-0000-4000-8000-000000000601',true);
do $$
declare
  by_default jsonb := public.herco_staff_booking_records(current_date+80,current_date+83,'PSORT');
  newest jsonb := public.herco_staff_booking_records(current_date+80,current_date+83,'PSORT','all','all',1,false,'date');
  oldest jsonb := public.herco_staff_booking_records(current_date+80,current_date+83,'PSORT','all','all',1,false,'date_asc');
  high jsonb := public.herco_staff_booking_records(current_date+80,current_date+83,'PSORT','all','all',1,false,'price');
  low jsonb := public.herco_staff_booking_records(current_date+80,current_date+83,'PSORT','all','all',1,false,'price_asc');
  by_status jsonb := public.herco_staff_booking_records(current_date+80,current_date+83,'PSORT','all','all',1,false,'status');
  first_row jsonb;
begin
  if public.herco_test_order(by_default) <> '4,3,2,1' or by_default->'records' <> newest->'records' then raise exception 'Default date order changed: %', public.herco_test_order(by_default); end if;
  if public.herco_test_order(oldest) <> '1,2,3,4' or oldest->>'sort' <> 'date_asc' then raise exception 'date_asc wrong: %', public.herco_test_order(oldest); end if;
  if public.herco_test_order(high) <> '1,2,3,4' then raise exception 'price (high to low) wrong: %', public.herco_test_order(high); end if;
  if public.herco_test_order(low) <> '3,2,1,4' or low->>'sort' <> 'price_asc' then raise exception 'price_asc wrong (edited price counts, no price last): %', public.herco_test_order(low); end if;
  if public.herco_test_order(by_status) <> '1,2,4,3' then raise exception 'status order changed: %', public.herco_test_order(by_status); end if;
  -- the edited price is the one shown as the total
  if (select (r->>'total_centavos')::bigint from jsonb_array_elements(low->'records') r where r->>'id' like '%6b2') <> 120000 then raise exception 'Total should be the edited price'; end if;
  -- search: name, phone, email, bike and reference all find S1
  if jsonb_array_length(public.herco_staff_booking_records(null,null,'zed fixture')->'records') <> 1
    or jsonb_array_length(public.herco_staff_booking_records(null,null,'9171110000')->'records') <> 1
    or jsonb_array_length(public.herco_staff_booking_records(null,null,'ZED@example.test')->'records') <> 1
    or jsonb_array_length(public.herco_staff_booking_records(null,null,'psort 1')->'records') <> 1 then raise exception 'Search by name, phone, email or bike failed'; end if;
  first_row := public.herco_staff_booking_records(null,null,'PSORT 1')->'records'->0;
  if not exists (select 1 from jsonb_array_elements(public.herco_staff_booking_records(null,null,first_row->>'reference')->'records') r where r->>'id' like '%6b1') then
    raise exception 'Search by reference failed'; end if;
end $$;
select public.herco_test_refused($s$select public.herco_staff_booking_records(null,null,'','all','all',1,false,'price_desc')$s$,'22023');
select public.herco_test_refused($s$select public.herco_staff_booking_records(null,null,'','all','all',1,false,'date_asc; drop table x')$s$,'22023');

-- 10. Without viewIncome: price sorts fall back to newest first, and amounts cannot be found by searching digits.
select set_config('test.uid','00000000-0000-4000-8000-000000000602',true);
do $$
declare
  low jsonb := public.herco_staff_booking_records(current_date+80,current_date+83,'PSORT','all','all',1,false,'price_asc');
  oldest jsonb := public.herco_staff_booking_records(current_date+80,current_date+83,'PSORT','all','all',1,false,'date_asc');
begin
  if public.herco_test_order(low) <> '4,3,2,1' or low->>'sort' <> 'date' then raise exception 'price_asc revealed order: %', public.herco_test_order(low); end if;
  if public.herco_test_order(oldest) <> '1,2,3,4' or oldest->>'sort' <> 'date_asc' then raise exception 'date_asc should still work: %', public.herco_test_order(oldest); end if;
  if low::text ~ '"(price_centavos|max_centavos)"' or exists (select 1 from jsonb_array_elements(low->'records') r where r->>'total_centavos' is not null) then
    raise exception 'A booking amount leaked'; end if;
  if jsonb_array_length(public.herco_staff_booking_records(null,null,'300000')->'records') <> 0
    or jsonb_array_length(public.herco_staff_booking_records(null,null,'price_centavos')->'records') <> 0 then raise exception 'An amount could be found by search'; end if;
end $$;
reset role;

-- 11. A disabled staff member loses access at once.
update herco_private.staff_memberships set enabled=false where user_id='00000000-0000-4000-8000-000000000602';
set local role authenticated;
select set_config('test.uid','00000000-0000-4000-8000-000000000602',true);
select public.herco_test_refused($s$select public.herco_staff_set_line_price('00000000-0000-4000-8000-0000000006a1',gen_random_uuid(),'wash',100000000,50000,'Disabled')$s$,'42501');
select public.herco_test_refused($s$select public.herco_booking_history('00000000-0000-4000-8000-0000000006a1')$s$,'42501');
reset role;

rollback;
