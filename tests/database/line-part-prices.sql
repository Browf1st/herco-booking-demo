-- Owner decision 2026-11-28: staff edit each PART of a service (base plus each option), with the line total auto-summed.
-- Tests the 7-argument herco_staff_set_line_price(..., parts). Fictional data only; rolled back.
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
  ('00000000-0000-4000-8000-000000000701','lp-owner@example.test',now()),
  ('00000000-0000-4000-8000-000000000702','lp-customer@example.test',now());
insert into herco_private.staff_memberships(user_id,role,page_grants,action_grants,display_name) values
  ('00000000-0000-4000-8000-000000000701','owner',array['Bookings'],array['viewIncome','adjustPrices'],'Owner');

-- A pending booking: a ceramic line with a 4-part breakdown, plus a plain wash line (no details).
insert into public.herco_bookings(id,customer_id,request_id,request_payload,visit_date,visit_hour,bike,customer_contact,status,original_services,original_total_centavos,current_services,current_total_centavos,service_revision,created_at) values
  ('00000000-0000-4000-8000-0000000007a1','00000000-0000-4000-8000-000000000702',gen_random_uuid(),'{}',current_date+30,10,'LPART bike','{}','pending',
   '[{"code":"ceramic","label":"Ceramic coating","price_centavos":259600,"details":[{"label":"Ceramic coating","price_centavos":179900},{"label":"Helmet coating","price_centavos":29900},{"label":"K3 bracket / crashguard removal","price_centavos":19900},{"label":"Mags coating","price_centavos":29900}]},{"code":"wash","label":"Wash","price_centavos":50000}]',309600,
   '[{"code":"ceramic","label":"Ceramic coating","price_centavos":259600,"details":[{"label":"Ceramic coating","price_centavos":179900},{"label":"Helmet coating","price_centavos":29900},{"label":"K3 bracket / crashguard removal","price_centavos":19900},{"label":"Mags coating","price_centavos":29900}]},{"code":"wash","label":"Wash","price_centavos":50000}]',309600,0,now());

set local role authenticated;
select set_config('test.uid','00000000-0000-4000-8000-000000000701',true);

-- 1. Edit two parts (base 1799→2999, Mags 299→8999); keep the breakdown and auto-sum to the new line total.
do $$
declare r jsonb; line jsonb;
begin
  r := public.herco_staff_set_line_price('00000000-0000-4000-8000-0000000007a1','00000000-0000-4000-8000-0000000007c1','ceramic',259600,1249600,'Owner reprice',
    '[{"price_centavos":299900},{"price_centavos":29900},{"price_centavos":19900},{"price_centavos":899900}]');
  if (r->>'revision')::int <> 1 then raise exception 'Revision should be 1: %', r; end if;
  line := (select l from jsonb_array_elements(r->'lines') l where l->>'code'='ceramic');
  if (line->>'price_centavos')::bigint <> 1249600 then raise exception 'Line total not summed: %', line; end if;
  if jsonb_array_length(line->'details') <> 4 then raise exception 'Breakdown lost: %', line; end if;
  if (line->'details'->0->>'price_centavos')::bigint <> 299900 or line->'details'->0->>'label' <> 'Ceramic coating'
    or (line->'details'->3->>'price_centavos')::bigint <> 899900 or line->'details'->3->>'label' <> 'Mags coating'
    or (line->'details'->1->>'price_centavos')::bigint <> 29900 then raise exception 'Parts wrong: %', line; end if;
  -- Line total includes the untouched wash line.
  if (r->>'totalCentavos')::bigint <> 1249600 + 50000 then raise exception 'Booking total wrong: %', r; end if;
end $$;
reset role;
do $$ begin
  if not exists (select 1 from herco_private.booking_price_edits where booking_id='00000000-0000-4000-8000-0000000007a1' and revision=1
    and service_code='ceramic' and previous_centavos=259600 and new_centavos=1249600
    and (previous_line->'details'->0->>'price_centavos')::bigint=179900) then raise exception 'Change not recorded with the old breakdown'; end if;
  -- The original snapshot is untouched.
  if not exists (select 1 from public.herco_bookings where id='00000000-0000-4000-8000-0000000007a1' and original_total_centavos=309600) then
    raise exception 'Original snapshot changed'; end if;
end $$;

-- 2. Refusals: parts not summing to the new price, a wrong part count, and a non-whole-peso part.
set local role authenticated;
select set_config('test.uid','00000000-0000-4000-8000-000000000701',true);
select public.herco_test_refused($s$select public.herco_staff_set_line_price('00000000-0000-4000-8000-0000000007a1',gen_random_uuid(),'ceramic',1249600,500000,'Mismatch','[{"price_centavos":100000},{"price_centavos":100000},{"price_centavos":100000},{"price_centavos":100000}]')$s$,'22023');
select public.herco_test_refused($s$select public.herco_staff_set_line_price('00000000-0000-4000-8000-0000000007a1',gen_random_uuid(),'ceramic',1249600,300000,'Wrong count','[{"price_centavos":100000},{"price_centavos":200000}]')$s$,'P0412');
select public.herco_test_refused($s$select public.herco_staff_set_line_price('00000000-0000-4000-8000-0000000007a1',gen_random_uuid(),'wash',50000,60050,'Centavos part','[{"price_centavos":60050}]')$s$,'22023');

-- 3. The flat (no parts) path still works on a plain line.
do $$
declare r jsonb;
begin
  r := public.herco_staff_set_line_price('00000000-0000-4000-8000-0000000007a1','00000000-0000-4000-8000-0000000007c2','wash',50000,70000,'Flat path',null);
  if (r->>'totalCentavos')::bigint <> 1249600 + 70000 then raise exception 'Flat edit total wrong: %', r; end if;
  if (select l from jsonb_array_elements(r->'lines') l where l->>'code'='wash') ? 'details' then raise exception 'Flat edit should have no details'; end if;
end $$;
reset role;

rollback;
