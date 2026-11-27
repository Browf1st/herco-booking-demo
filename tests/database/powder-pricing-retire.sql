-- F-021 step 2 (migration 202611260002): the legacy coating price rules engine is gone and pricing still works.
-- Run against a fresh local or CI database after every migration. Fictional data only; everything is rolled back.
begin;

insert into auth.users(id,email,email_confirmed_at) values
  ('00000000-0000-4000-8000-000000000711','pr-customer@example.test',now()),
  ('00000000-0000-4000-8000-000000000712','pr-owner@example.test',now());
insert into herco_private.staff_memberships(user_id,role,page_grants,action_grants) values
  ('00000000-0000-4000-8000-000000000712','owner',array['Pricing'],array['changePricing']);
select set_config('test.aal','aal2',true);

-- 1. The table and its editor functions are gone; nothing live mentions the table; the archive exists and is private.
do $$ begin
  if to_regclass('herco_private.coating_price_rules') is not null then raise exception 'coating_price_rules still exists'; end if;
  if to_regprocedure('public.herco_coating_rules()') is not null
    or to_regprocedure('public.herco_save_coating_rule(uuid,uuid,integer,text,text,jsonb,integer,integer,boolean,boolean)') is not null then raise exception 'Editor functions still exist'; end if;
  if exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in('public','herco_private') and p.prosrc like '%coating_price_rules%'
    and p.proname <> 'retire_coating_price_rules_data') then raise exception 'A function still reads coating_price_rules'; end if;
  if to_regclass('herco_private.coating_price_rules_archive') is null then raise exception 'Archive table missing'; end if;
  if has_table_privilege('authenticated','herco_private.coating_price_rules_archive','select') or has_table_privilege('anon','herco_private.coating_price_rules_archive','select') then
    raise exception 'Archive is readable by browser roles'; end if;
  if has_function_privilege('authenticated','herco_private.coating_price_lines_legacy(jsonb,text,jsonb)','execute') then raise exception 'Legacy resolver is callable'; end if;
end $$;

-- 2. Fixture: pricing config with the seeded powder model, an enabled powder service, a saved booking.
update herco_private.ui_pricing set config='{
 "ceramic":{"tiers":{"1799":1799,"1999":1999,"2499":2499},"addons":{"Matte to Glossy":100,"Inner coating":100,"Graphene coating":100,"Mags coating":100,"Helmet coating":100,"K3 bracket / crashguard removal":100,"Decals removal":100},
  "listedAddons":{"Matte to Glossy":100,"Inner coating":100,"Graphene coating":100},"premiumGloss":5000},
 "powder":{"parts":{"Swingarm":[500,500]},"wheelRates":{"10–14 inches":[2000,2000]},"prismatic":{"10–14 inches":2500},"extras":{"Aftermarket mags":100},"largeSwingarm":[900,900]}}'::jsonb
  || jsonb_build_object('powderModel',config->'powderModel') where singleton;
insert into herco_private.services(code,label,price_centavos,enabled) values('wheel-colour','Powder coating',100000,true)
  on conflict (code) do update set enabled=true;
insert into public.herco_bookings(id,customer_id,request_id,request_payload,visit_date,visit_hour,bike,customer_contact,status,original_services,original_total_centavos,coating_options,created_at) values
  ('00000000-0000-4000-8000-0000000007a2','00000000-0000-4000-8000-000000000711',gen_random_uuid(),'{}',current_date+91,10,'PR FIXTURE','{}','pending',
   '[{"code":"wheel-colour","label":"Powder coating","price_centavos":219900,"coating_rule_id":"00000000-0000-4000-8000-0000000007f1"}]',219900,'{"ui_catalog":{"wheel_type":"10–14 inches","finish":"Black"}}',now());
select set_config('pr.before',md5((select original_services::text||original_total_centavos::text||coating_options::text from public.herco_bookings where id='00000000-0000-4000-8000-0000000007a2')),true);

-- 3. New powder pricing still works: the resolver used by create, walk-in and edit, and the customer preview.
do $$
declare l jsonb;
begin
  l := herco_private.coating_price_lines('[{"code":"wheel-colour","label":"Powder coating"}]'::jsonb,'Yamaha Mio',
    '{"powder_parts":["Wheels / mags"],"ui_catalog":{"wheel_type":"17 inches (Raider / Sniper only)","finish":"Fire Blue"}}'::jsonb)->0;
  if (l->>'price_centavos')::bigint <> 349900 then raise exception 'Powder wheel price wrong after retirement: %', l; end if;
  l := herco_private.coating_price_lines('[{"code":"wheel-colour","label":"Powder coating"}]'::jsonb,'Yamaha Mio',
    '{"powder_parts":["Wheels / mags"],"ui_catalog":{"wheel_type":"Not sure","finish":"Fire Blue"}}'::jsonb)->0;
  if l->>'quote_required' <> 'true' then raise exception 'Not sure should quote: %', l; end if;
  -- Options without ui_catalog no longer read any rules: the catalog line is returned unchanged.
  l := herco_private.coating_price_lines('[{"code":"wheel-colour","label":"Powder coating","price_centavos":100000}]'::jsonb,'Yamaha Mio','{"powder_parts":["Wheels / mags"],"wheel_front":"Not sure"}'::jsonb)->0;
  if (l->>'price_centavos')::bigint <> 100000 then raise exception 'Legacy options should keep the catalog price: %', l; end if;
end $$;
set local role authenticated;
select set_config('test.uid','00000000-0000-4000-8000-000000000711',true);
do $$
declare p jsonb := public.herco_preview_coating_price('Yamaha Mio',array['wheel-colour'],
  '{"powder_parts":["Wheels / mags"],"wheel_front":"Not sure","ui_catalog":{"wheel_type":"10–14 inches","finish":"Black"}}'::jsonb);
begin
  if (p->'lines'->0->>'price_centavos')::bigint <> 219900 or (p->>'totalCentavos')::bigint <> 219900 then raise exception 'Preview price wrong: %', p; end if;
end $$;
reset role;

-- 4. Staff can still save pricing (the model flows through); the removed editor is not callable.
set local role authenticated;
select set_config('test.uid','00000000-0000-4000-8000-000000000712',true);
do $$
declare r jsonb := public.herco_save_ui_pricing(gen_random_uuid(),(public.herco_staff_ui_pricing()->>'revision')::int,public.herco_staff_ui_pricing()->'config');
begin if r->'config'->'powderModel' is null then raise exception 'Save lost the powder model'; end if; end $$;
reset role;

-- 5. A saved booking is untouched by all of the above (byte-identical snapshot, including its old rule id note).
do $$ begin
  if md5((select original_services::text||original_total_centavos::text||coating_options::text from public.herco_bookings where id='00000000-0000-4000-8000-0000000007a2')) <> current_setting('pr.before')
    or not exists(select 1 from public.herco_bookings where id='00000000-0000-4000-8000-0000000007a2' and original_total_centavos=219900
      and original_services->0->>'coating_rule_id'='00000000-0000-4000-8000-0000000007f1') then raise exception 'A saved booking changed'; end if;
end $$;

-- 6. The data move in 0002, exercised on sample rules. The real table is already gone, so the test recreates a plain
--    copy (no foreign keys) inside this transaction, runs the migration's function, and checks the result.
create table herco_private.coating_price_rules(id uuid primary key, service_code text not null, bike_key text not null default '',
  option_match jsonb not null, minimum_centavos integer not null, maximum_centavos integer, quote_required boolean not null default false, enabled boolean not null default false);
insert into herco_private.coating_price_rules(id,service_code,bike_key,option_match,minimum_centavos,maximum_centavos,quote_required,enabled) values
  ('00000000-0000-4000-8000-0000000007a1','wheel-colour','honda pcx160','{"finish":"Black","powder_parts":["Wheels / mags"]}',350000,null,false,true),
  ('00000000-0000-4000-8000-0000000007a2','wheel-colour','yamaha mio','{"finish":"Fire Blue"}',0,null,true,true),
  ('00000000-0000-4000-8000-0000000007a3','wheel-colour','honda pcx160','{"finish":"black"}',400000,null,false,true),
  ('00000000-0000-4000-8000-0000000007a4','wheel-colour','suzuki raider','{"powder_parts":["Wheels / mags"]}',250000,null,false,true),
  ('00000000-0000-4000-8000-0000000007a5','wheel-colour','honda click125','{"finish":"Matte Black"}',280000,null,false,false),
  ('00000000-0000-4000-8000-0000000007a6','ceramic','honda pcx160','{"ceramic_finish":"Enhance"}',500000,null,false,true);
select set_config('pr.rev',(select revision::text from herco_private.ui_pricing where singleton),true);
select herco_private.retire_coating_price_rules_data();
do $$
declare ex jsonb := (select config->'powderModel'->'exceptions' from herco_private.ui_pricing where singleton);
  a jsonb; b jsonb;
begin
  if jsonb_array_length(ex) <> 2 then raise exception 'Expected 2 migrated exceptions, got %', ex; end if;
  select e into a from jsonb_array_elements(ex) e where e->>'note'='migrated:00000000-0000-4000-8000-0000000007a1';
  select e into b from jsonb_array_elements(ex) e where e->>'note'='migrated:00000000-0000-4000-8000-0000000007a2';
  if a is null or a->>'bikeKey'<>'honda pcx160' or a->>'finish'<>'Black' or (a->>'priceCentavos')::int<>350000 or a->'enabled'<>'true'::jsonb or a->>'service'<>'wheel-colour' or a ? 'quoteOnly' then raise exception 'Priced rule not migrated: %', a; end if;
  if b is null or b->>'bikeKey'<>'yamaha mio' or b->'quoteOnly'<>'true'::jsonb or b ? 'priceCentavos' then raise exception 'Quote rule not migrated: %', b; end if;
  if exists(select 1 from jsonb_array_elements(ex) e where e->>'note' like '%7a3' or e->>'note' like '%7a4' or e->>'note' like '%7a5' or e->>'note' like '%7a6') then
    raise exception 'A duplicate, finish-less, disabled or ceramic rule became an exception: %', ex; end if;
  if (select revision from herco_private.ui_pricing where singleton) <> current_setting('pr.rev')::int + 1 then raise exception 'Revision should go up once'; end if;
  if not herco_private.valid_powder_model((select config->'powderModel' from herco_private.ui_pricing where singleton)) then raise exception 'Model invalid after the move'; end if;
  -- every original row is kept in the archive, unchanged
  if (select count(*) from herco_private.coating_price_rules r join herco_private.coating_price_rules_archive a on a.id=r.id and a.rule=to_jsonb(r)) <> 6 then raise exception 'Archive is missing rules'; end if;
end $$;
-- A second run changes nothing.
select herco_private.retire_coating_price_rules_data();
do $$ begin
  if jsonb_array_length((select config->'powderModel'->'exceptions' from herco_private.ui_pricing where singleton)) <> 2
    or (select revision from herco_private.ui_pricing where singleton) <> current_setting('pr.rev')::int + 1 then raise exception 'The data move is not idempotent'; end if;
end $$;
-- The migrated exceptions override the base price on the live resolver, and everything else still quotes or uses base.
do $$ begin
  if (herco_private.coating_price_lines('[{"code":"wheel-colour"}]'::jsonb,'Honda PCX160','{"powder_parts":["Wheels / mags"],"ui_catalog":{"wheel_type":"10–14 inches","finish":"Black"}}'::jsonb)->0->>'price_centavos')::bigint <> 350000
   then raise exception 'Migrated exception not applied'; end if;
end $$;
drop table herco_private.coating_price_rules;
select herco_private.retire_coating_price_rules_data(); -- harmless once the table is gone

rollback;
