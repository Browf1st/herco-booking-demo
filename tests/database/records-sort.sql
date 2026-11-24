-- Booking Reports: sorting, paging and income hiding of herco_staff_booking_records. Fictional data only; rolled back.
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

insert into auth.users(id,email,email_confirmed_at) values
  ('00000000-0000-4000-8000-000000000401','records-income@example.test',now()),
  ('00000000-0000-4000-8000-000000000402','records-noincome@example.test',now()),
  ('00000000-0000-4000-8000-000000000403','records-customer@example.test',now());
insert into herco_private.staff_memberships(user_id,role,page_grants,action_grants) values
  ('00000000-0000-4000-8000-000000000401','staff',array['Bookings'],array['viewIncome']),
  ('00000000-0000-4000-8000-000000000402','staff',array['Bookings'],array[]::text[]);

-- Named fixtures (bike names start with RSORT). Estimates are in centavos; done bookings also get a final price.
insert into public.herco_bookings(id,customer_id,request_id,request_payload,visit_date,visit_hour,bike,customer_contact,status,original_services,original_total_centavos,created_at) values
  ('00000000-0000-4000-8000-0000000004a1','00000000-0000-4000-8000-000000000403',gen_random_uuid(),'{}',current_date+60,10,'RSORT pending','{}','pending','[{"code":"a","label":"Wash","price_centavos":500000,"details":[{"label":"Foam","price_centavos":1000}]}]',500000,now()-interval '5 hours'),
  ('00000000-0000-4000-8000-0000000004a2','00000000-0000-4000-8000-000000000403',gen_random_uuid(),'{}',current_date+60,10,'RSORT booked','{}','confirmed','[{"code":"b","label":"Ceramic","price_centavos":900000}]',900000,now()-interval '4 hours'),
  ('00000000-0000-4000-8000-0000000004a3','00000000-0000-4000-8000-000000000403',gen_random_uuid(),'{}',current_date+60,10,'RSORT done high final','{}','done','[{"code":"c","label":"Polish","price_centavos":100000}]',100000,now()-interval '3 hours'),
  ('00000000-0000-4000-8000-0000000004a4','00000000-0000-4000-8000-000000000403',gen_random_uuid(),'{}',current_date+60,10,'RSORT done low final','{}','done','[{"code":"c","label":"Polish","price_centavos":950000}]',950000,now()-interval '2 hours'),
  ('00000000-0000-4000-8000-0000000004a5','00000000-0000-4000-8000-000000000403',gen_random_uuid(),'{}',current_date+60,10,'RSORT cancelled','{}','cancelled','[{"code":"a","label":"Wash","price_centavos":200000}]',200000,now()-interval '1 hours'),
  ('00000000-0000-4000-8000-0000000004a6','00000000-0000-4000-8000-000000000403',gen_random_uuid(),'{}',current_date+60,10,'RSORT done no final','{}','done','[{"code":"b","label":"Ceramic","price_centavos":990000}]',990000,now());
insert into herco_private.booking_completion(booking_id,actor_id,final_price_centavos,photo_paths,note) values
  ('00000000-0000-4000-8000-0000000004a3','00000000-0000-4000-8000-000000000401',700000,array['fixture/a.jpg'],'Fixture note'),
  ('00000000-0000-4000-8000-0000000004a4','00000000-0000-4000-8000-000000000401',300000,array['fixture/b.jpg'],'Fixture note');

-- Helper: ordered fixture ids (last hex digit) from a result, as text like "1,2,3".
create function public.herco_test_order(result jsonb) returns text language sql immutable as $$
  select string_agg(right(r->>'id',1),',' order by n) from jsonb_array_elements(result->'records') with ordinality t(r,n)
$$;

set local role authenticated;
select set_config('test.uid','00000000-0000-4000-8000-000000000401',true);

-- 1. Default and explicit "date": same order as before (newest created first for a shared date).
do $$
declare
  by_default jsonb := public.herco_staff_booking_records(current_date+60,current_date+60,'RSORT');
  by_date jsonb := public.herco_staff_booking_records(current_date+60,current_date+60,'RSORT','all','all',1,false,'date');
begin
  if public.herco_test_order(by_default) <> '6,5,4,3,2,1' then raise exception 'Default order changed: %', public.herco_test_order(by_default); end if;
  if by_default->'records' <> by_date->'records' then raise exception 'sort=date differs from the default'; end if;
  if by_default->>'sort' <> 'date' or (by_default->>'total')::int <> 6 then raise exception 'Unexpected sort/total: %', by_default; end if;
end $$;

-- 2. Price: done uses the final price, others use the estimate; done without a final price goes last.
--    Values: 2=900000, 5=200000, 1=500000, 3=final 700000, 4=final 300000, 6=none.
do $$
declare by_price jsonb := public.herco_staff_booking_records(current_date+60,current_date+60,'RSORT','all','all',1,false,'price');
begin
  if public.herco_test_order(by_price) <> '2,3,1,4,5,6' then raise exception 'Price order wrong: %', public.herco_test_order(by_price); end if;
  if by_price->>'sort' <> 'price' then raise exception 'sort not reported'; end if;
end $$;

-- 3. Status: pending, booked, done, cancelled; ties by newest first.
do $$
declare by_status jsonb := public.herco_staff_booking_records(current_date+60,current_date+60,'RSORT','all','all',1,false,'status');
begin
  if public.herco_test_order(by_status) <> '1,2,6,4,3,5' then raise exception 'Status order wrong: %', public.herco_test_order(by_status); end if;
end $$;

-- 4. Estimate is returned for staff who can view income, next to the final price.
do $$
declare rec jsonb;
begin
  select r into rec from jsonb_array_elements(public.herco_staff_booking_records(current_date+60,current_date+60,'RSORT pending')->'records') r;
  if (rec->>'original_total_centavos')::bigint <> 500000 or (rec->'original_services'->0->>'price_centavos')::bigint <> 500000 then
    raise exception 'Estimate missing: %', rec; end if;
  select r into rec from jsonb_array_elements(public.herco_staff_booking_records(current_date+60,current_date+60,'RSORT done high')->'records') r;
  if (rec->>'final_price_centavos')::bigint <> 700000 or (rec->>'original_total_centavos')::bigint <> 100000 then raise exception 'Final or estimate wrong: %', rec; end if;
end $$;

-- 5. Paging is stable across all records: 30 more bookings with identical prices, every sort, three pages, no repeats or gaps.
reset role;
insert into public.herco_bookings(customer_id,request_id,request_payload,visit_date,visit_hour,bike,customer_contact,status,original_services,original_total_centavos)
  select '00000000-0000-4000-8000-000000000403',gen_random_uuid(),'{}',current_date+61,10,'RPAGE '||g,'{}',case when g%2=0 then 'pending' else 'confirmed' end,'[]',100000 from generate_series(1,45) g;
set local role authenticated;
do $$
declare s text; p integer; seen uuid[]; page jsonb; ids uuid[];
begin
  foreach s in array array['date','price','status'] loop
    seen := '{}';
    for p in 1..3 loop
      page := public.herco_staff_booking_records(current_date+61,current_date+61,'RPAGE','all','all',p,false,s);
      select coalesce(array_agg((r->>'id')::uuid),'{}') into ids from jsonb_array_elements(page->'records') r;
      if cardinality(ids) <> case when p < 3 then 20 else 5 end then raise exception 'Page % of % has % rows', p, s, cardinality(ids); end if;
      if seen && ids then raise exception 'A booking repeats between pages (sort %)', s; end if;
      seen := seen || ids;
    end loop;
    if cardinality(seen) <> 45 or (page->>'pages')::int <> 3 then raise exception 'Paging lost rows (sort %)', s; end if;
  end loop;
end $$;

-- 6. Bad sort values and permissions.
select public.herco_test_refused($s$select public.herco_staff_booking_records(null,null,'','all','all',1,false,'name')$s$,'22023');
select public.herco_test_refused($s$select public.herco_staff_booking_records(null,null,'','all','all',1,false,'price; drop table x')$s$,'22023');
select public.herco_test_refused($s$select public.herco_staff_booking_records(null,null,'','all','all',1,false,null)$s$,'22023');
select public.herco_test_refused($s$select public.herco_staff_booking_records(null,null,'','all','all',1,true,'date')$s$,'42501');

-- 7. Without viewIncome: no amounts anywhere in the rows, and price sorting cannot reveal order.
select set_config('test.uid','00000000-0000-4000-8000-000000000402',true);
do $$
declare
  result jsonb := public.herco_staff_booking_records(current_date+60,current_date+60,'RSORT','all','all',1,false,'price');
  text_result text := result::text;
begin
  if (result->>'canViewIncome')::boolean then raise exception 'canViewIncome should be false'; end if;
  if result->>'sort' <> 'date' or public.herco_test_order(result) <> '6,5,4,3,2,1' then raise exception 'Price sort revealed order: %', public.herco_test_order(result); end if;
  if text_result ~ '(price_centavos|max_centavos|promotion)' then raise exception 'A service amount leaked'; end if;
  if exists (select 1 from jsonb_array_elements(result->'records') r where r->>'final_price_centavos' is not null
    or r->>'original_total_centavos' is not null or r->>'total_centavos' is not null) then raise exception 'A booking total leaked'; end if;
  if not exists (select 1 from jsonb_array_elements(result->'records') r where r->'original_services'->0->>'label' = 'Wash') then
    raise exception 'Service labels should still be returned'; end if;
  if (public.herco_staff_booking_records(current_date+60,current_date+60,'RSORT')->'records'->0->'original_services'->0) ? 'price_centavos' then raise exception 'Default sort leaked a price'; end if;
end $$;

-- 8. A customer and a signed-out caller cannot read records.
select set_config('test.uid','00000000-0000-4000-8000-000000000403',true);
select public.herco_test_refused($s$select public.herco_staff_booking_records(null,null,'','all','all',1,false,'price')$s$,'42501');
reset role;
set local role anon;
select set_config('test.uid','',true);
select public.herco_test_refused($s$select public.herco_staff_booking_records(null,null,'','all','all',1,false,'date')$s$,'42501');
reset role;

rollback;
