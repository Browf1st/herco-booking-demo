-- Owner decision 2026-11-28: staff can open one booking's full details from the Customers directory.
-- herco_staff_booking_detail is gated to staff (Customers/Bookings/Booking history/Reports) and strips money
-- without viewIncome. Fictional data only; rolled back.
begin;

insert into auth.users(id,email,email_confirmed_at) values
  ('00000000-0000-4000-8000-0000000006a1','detail-income@example.test',now()),
  ('00000000-0000-4000-8000-0000000006a2','detail-noincome@example.test',now()),
  ('00000000-0000-4000-8000-0000000006a3','detail-customer@example.test',now());
insert into herco_private.staff_memberships(user_id,role,page_grants,action_grants) values
  ('00000000-0000-4000-8000-0000000006a1','staff',array['Customers'],array['viewIncome']),
  ('00000000-0000-4000-8000-0000000006a2','staff',array['Customers'],array[]::text[]);

insert into public.herco_bookings(id,customer_id,request_id,request_payload,visit_date,visit_hour,bike,customer_contact,status,original_services,original_total_centavos,created_at) values
  ('00000000-0000-4000-8000-0000000006b1','00000000-0000-4000-8000-0000000006a3',gen_random_uuid(),'{}',current_date+2,10,'DETAIL bike','{}','confirmed',
   '[{"code":"ceramic","label":"Ceramic coating","price_centavos":179900,"details":[{"label":"Ceramic coating","price_centavos":179900}]}]',179900,now());

set local role authenticated;

-- Staff with Customers + viewIncome sees the booking and its money.
select set_config('test.uid','00000000-0000-4000-8000-0000000006a1',true);
do $$
declare d jsonb := public.herco_staff_booking_detail('00000000-0000-4000-8000-0000000006b1');
begin
  if d->>'id' <> '00000000-0000-4000-8000-0000000006b1' then raise exception 'Wrong booking: %', d; end if;
  if (d->>'canViewIncome')::boolean is not true then raise exception 'viewIncome should be true'; end if;
  if (d->>'total_centavos')::bigint <> 179900 then raise exception 'Total missing: %', d; end if;
end $$;

-- Staff with Customers but no viewIncome: labels stay, amounts stripped.
select set_config('test.uid','00000000-0000-4000-8000-0000000006a2',true);
do $$
declare d jsonb := public.herco_staff_booking_detail('00000000-0000-4000-8000-0000000006b1');
begin
  if (d->>'canViewIncome')::boolean is not false then raise exception 'viewIncome should be false'; end if;
  if d::text ~ '"price_centavos"' or d->>'total_centavos' is not null then raise exception 'An amount leaked: %', d; end if;
  if d->'current_services'->0->>'label' <> 'Ceramic coating' then raise exception 'Service label missing: %', d; end if;
end $$;

-- A customer cannot read it.
select set_config('test.uid','00000000-0000-4000-8000-0000000006a3',true);
do $$
begin
  perform public.herco_staff_booking_detail('00000000-0000-4000-8000-0000000006b1');
  raise exception 'A customer reached staff booking detail';
exception when sqlstate '42501' then null;
end $$;

-- Unknown booking is a 404-style P0002.
select set_config('test.uid','00000000-0000-4000-8000-0000000006a1',true);
do $$
begin
  perform public.herco_staff_booking_detail('00000000-0000-4000-8000-00000000ffff');
  raise exception 'Unknown booking did not raise';
exception when sqlstate 'P0002' then null;
end $$;

reset role;
rollback;
