-- F-024 (migration 202611260005): the customer-safe booking history. Fictional data only; everything is rolled back.
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
  ('00000000-0000-4000-8000-000000000741','ch-staff@example.test',now()),
  ('00000000-0000-4000-8000-000000000742','ch-owner-customer@example.test',now()),
  ('00000000-0000-4000-8000-000000000743','ch-other-customer@example.test',now());
insert into herco_private.staff_memberships(user_id,role,page_grants,action_grants,display_name) values
  ('00000000-0000-4000-8000-000000000741','owner',array['Bookings'],array['adjustPrices','viewIncome'],'Secret Staffname');

insert into public.herco_bookings(id,customer_id,request_id,request_payload,visit_date,visit_hour,bike,customer_contact,status,original_services,original_total_centavos,created_at) values
  ('00000000-0000-4000-8000-0000000007b1','00000000-0000-4000-8000-000000000742',gen_random_uuid(),'{}',current_date+60,10,'CH BIKE',
   '{"name":"Private Customer Name","email":"private-contact@example.test","phone":"+639170001111"}','confirmed',
   '[{"code":"ceramic","label":"Ceramic coating","price_centavos":179900}]',179900,now()-interval '6 days');
update public.herco_bookings set current_services='[{"code":"ceramic","label":"Ceramic coating","price_centavos":230000},{"code":"helmet","label":"Helmet coating","price_centavos":29900}]',
  current_total_centavos=259900,service_revision=2 where id='00000000-0000-4000-8000-0000000007b1';
insert into herco_private.booking_price_edits(booking_id,revision,actor_id,request_id,service_code,service_label,previous_centavos,new_centavos,reason,previous_line) values
  ('00000000-0000-4000-8000-0000000007b1',2,'00000000-0000-4000-8000-000000000741',gen_random_uuid(),'ceramic','Ceramic coating',179900,230000,'SECRET REASON corrosion found',
   '{"code":"ceramic","label":"Ceramic coating","price_centavos":179900}');
insert into herco_private.booking_service_changes(booking_id,actor_id,request_id,revision,service_codes,before_services,after_services,recorded_at) values
  ('00000000-0000-4000-8000-0000000007b1','00000000-0000-4000-8000-000000000742',gen_random_uuid(),1,array['ceramic','helmet'],
   '[{"code":"ceramic","label":"Ceramic coating","price_centavos":179900}]',
   '[{"code":"ceramic","label":"Ceramic coating","price_centavos":179900},{"code":"helmet","label":"Helmet coating","price_centavos":29900}]',now()-interval '4 days');
insert into public.herco_booking_events(booking_id,actor_id,kind,to_status,created_at) values
  ('00000000-0000-4000-8000-0000000007b1','00000000-0000-4000-8000-000000000742','booking_submitted','pending',now()-interval '6 days'),
  ('00000000-0000-4000-8000-0000000007b1','00000000-0000-4000-8000-000000000741','booking_confirmed','confirmed',now()-interval '5 days');
-- A booking with no changes.
insert into public.herco_bookings(id,customer_id,request_id,request_payload,visit_date,visit_hour,bike,customer_contact,status,original_services,original_total_centavos) values
  ('00000000-0000-4000-8000-0000000007b2','00000000-0000-4000-8000-000000000742',gen_random_uuid(),'{}',current_date+61,10,'CH EMPTY','{}','pending','[]',0);

-- The owner reads it: newest first, from/to amounts, actor you/shop, labels, no staff name, reason, contact or notes.
set local role authenticated;
select set_config('test.uid','00000000-0000-4000-8000-000000000742',true);
do $$
declare h jsonb := public.herco_customer_booking_history('00000000-0000-4000-8000-0000000007b1'); kinds text;
begin
  select string_agg(e->>'kind',',' order by n) into kinds from jsonb_array_elements(h->'entries') with ordinality t(e,n);
  if kinds <> 'price_changed,service_added,approved,booked' then raise exception 'Entries wrong: %', h; end if;
  if h->>'booking_id' <> '00000000-0000-4000-8000-0000000007b1' or (select array_agg(k order by k) from jsonb_object_keys(h) k) <> array['booking_id','entries'] then raise exception 'Shape wrong: %', h; end if;
  if h->'entries'->0->>'actor' <> 'shop' or (h->'entries'->0->>'from_centavos')::bigint <> 179900 or (h->'entries'->0->>'to_centavos')::bigint <> 230000
    or h->'entries'->0->>'service_label' <> 'Ceramic coating' then raise exception 'Price entry wrong: %', h->'entries'->0; end if;
  if h->'entries'->1->>'actor' <> 'you' or h->'entries'->1->>'service_label' <> 'Helmet coating' or (h->'entries'->1->>'to_centavos')::bigint <> 29900
    or h->'entries'->1 ? 'from_centavos' then raise exception 'Added entry wrong: %', h->'entries'->1; end if;
  if h->'entries'->2->>'actor' <> 'shop' or h->'entries'->3->>'actor' <> 'you' then raise exception 'Status actors wrong: %', h; end if;
  if exists(select 1 from jsonb_array_elements(h->'entries') e, jsonb_object_keys(e) k where k not in('at','kind','actor','service_label','from_centavos','to_centavos'))
    then raise exception 'An unexpected field appeared: %', h; end if;
  if h::text ~* '(Secret Staffname|SECRET REASON|reason|private-contact|Private Customer|\+63|HERCO staff|@)' then raise exception 'Private data leaked: %', h; end if;
  -- no changes: an empty list, not an error
  if public.herco_customer_booking_history('00000000-0000-4000-8000-0000000007b2')->'entries' <> '[]'::jsonb then raise exception 'Empty log should be an empty list'; end if;
end $$;

-- Another customer, a missing booking and a null id are all refused the same way.
select set_config('test.uid','00000000-0000-4000-8000-000000000743',true);
select public.herco_test_refused($s$select public.herco_customer_booking_history('00000000-0000-4000-8000-0000000007b1')$s$,'42501');
select public.herco_test_refused($s$select public.herco_customer_booking_history(gen_random_uuid())$s$,'42501');
select public.herco_test_refused($s$select public.herco_customer_booking_history(null)$s$,'42501');
-- Staff who do not own the booking get no customer view (they use the staff history).
select set_config('test.uid','00000000-0000-4000-8000-000000000741',true);
select public.herco_test_refused($s$select public.herco_customer_booking_history('00000000-0000-4000-8000-0000000007b1')$s$,'42501');
reset role;
set local role anon;
select set_config('test.uid','',true);
select public.herco_test_refused($s$select public.herco_customer_booking_history('00000000-0000-4000-8000-0000000007b1')$s$,'42501');
reset role;
do $$ begin
  if has_function_privilege('anon','public.herco_customer_booking_history(uuid)','execute') or has_function_privilege('public','public.herco_customer_booking_history(uuid)','execute')
    or not has_function_privilege('authenticated','public.herco_customer_booking_history(uuid)','execute') then raise exception 'Wrong grants'; end if;
end $$;

rollback;
