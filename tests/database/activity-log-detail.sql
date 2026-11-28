-- Owner decision 2026-11-28: the Activity log Bookings rows state what changed (price from→to, added/removed service),
-- with the HG-n reference. Fictional data only; rolled back.
begin;

insert into auth.users(id,email,email_confirmed_at) values
  ('00000000-0000-4000-8000-0000000005a1','activity-owner@example.test',now()),
  ('00000000-0000-4000-8000-0000000005a2','activity-customer@example.test',now());
insert into herco_private.staff_memberships(user_id,role,page_grants,action_grants) values
  ('00000000-0000-4000-8000-0000000005a1','owner',array['Activity log'],array['viewIncome']);

insert into public.herco_bookings(id,customer_id,request_id,request_payload,visit_date,visit_hour,bike,customer_contact,status,original_services,original_total_centavos,created_at) values
  ('00000000-0000-4000-8000-0000000005b1','00000000-0000-4000-8000-0000000005a2',gen_random_uuid(),'{}',current_date+3,10,'ALOG bike','{}','confirmed',
   '[{"code":"powder","label":"Powder Coating","price_centavos":199900}]',199900,now());

-- A staff line-price edit (Powder Coating ₱1,999 → ₱2,999) and an added service.
insert into herco_private.booking_price_edits(booking_id,revision,actor_id,request_id,service_code,service_label,previous_centavos,new_centavos,reason,previous_line,recorded_at) values
  ('00000000-0000-4000-8000-0000000005b1',1,'00000000-0000-4000-8000-0000000005a1',gen_random_uuid(),'powder','Powder Coating',199900,299900,'Owner reprice',
   '{"code":"powder","label":"Powder Coating","price_centavos":199900}',now());
insert into herco_private.booking_service_changes(booking_id,actor_id,request_id,revision,service_codes,before_services,after_services,recorded_at) values
  ('00000000-0000-4000-8000-0000000005b1','00000000-0000-4000-8000-0000000005a1',gen_random_uuid(),1,array['mags'],
   '[{"code":"powder","label":"Powder Coating","price_centavos":199900}]',
   '[{"code":"powder","label":"Powder Coating","price_centavos":199900},{"code":"mags","label":"Mags coating","price_centavos":29900}]',now());

set local role authenticated;
select set_config('test.uid','00000000-0000-4000-8000-0000000005a1',true);
select set_config('test.aal','aal2',true);

do $$
declare rows jsonb;
begin
  select coalesce(jsonb_agg(to_jsonb(a)),'[]') into rows from public.herco_staff_activity(current_date,current_date) a where a.area='Bookings';
  if not exists (select 1 from jsonb_array_elements(rows) r
    where r->>'action' = 'Powder Coating price ₱1,999 → ₱2,999' and r->>'reference' like 'HG-%') then
    raise exception 'Price-change detail missing: %', rows; end if;
  if not exists (select 1 from jsonb_array_elements(rows) r where r->>'action' = 'Added Mags coating (₱299)') then
    raise exception 'Added-service detail missing: %', rows; end if;
end $$;

-- A non-owner is still refused.
reset role;
insert into auth.users(id,email,email_confirmed_at) values ('00000000-0000-4000-8000-0000000005a3','activity-admin@example.test',now());
insert into herco_private.staff_memberships(user_id,role,page_grants,action_grants) values
  ('00000000-0000-4000-8000-0000000005a3','admin',array['Activity log'],array['viewIncome']);
set local role authenticated;
select set_config('test.uid','00000000-0000-4000-8000-0000000005a3',true);
select set_config('test.aal','aal2',true);
do $$
begin
  perform public.herco_staff_activity(current_date,current_date);
  raise exception 'A non-owner reached the activity log';
exception when sqlstate '42501' then null;
end $$;

reset role;
rollback;
