-- F-023 (migration 202611260004): staff per-bike ceramic prices via powderModel.exceptions with service 'ceramic'.
-- Run against a fresh local or CI database after every migration. Fictional data only; everything is rolled back.
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
create function public.herco_test_bad(mutated jsonb, state text default '22023') returns void language plpgsql as $$
begin
  perform public.herco_save_ui_pricing(gen_random_uuid(), public.herco_test_rev(), mutated);
  raise exception 'NOT REFUSED: %', left(mutated::text, 200);
exception when others then
  if sqlstate is distinct from state then
    raise exception 'Expected % but got % (%) for: %', state, sqlstate, sqlerrm, left(mutated::text, 200);
  end if;
end $$;
create function public.herco_test_is(actual text, expected text, label text) returns void language plpgsql as $$
begin
  if actual is distinct from expected then raise exception '% expected % but got %', label, expected, actual; end if;
end $$;
create function public.herco_test_cfg() returns jsonb language sql stable security definer set search_path='' as $$
  select config from herco_private.ui_pricing where singleton $$;
create function public.herco_test_rev() returns integer language sql stable security definer set search_path='' as $$
  select revision from herco_private.ui_pricing where singleton $$;
create function public.herco_test_cex(patch jsonb default '{}') returns jsonb language sql immutable as $$
  select '{"id":"00000000-0000-4000-8000-0000000007f1","service":"ceramic","bikeKey":"honda click125","priceCentavos":220000,"enabled":true,"note":"Fixture"}'::jsonb || patch $$;
-- Customer preview of the ceramic line: 'quote' or centavos. addons is a json array of add-on names.
create function public.herco_test_ceramic(bike text, addons jsonb default '[]') returns text language plpgsql stable as $$
declare p jsonb := public.herco_preview_coating_price(bike,array['ceramic'],jsonb_build_object('ui_catalog',jsonb_build_object('ceramic_addons',addons)));
begin
  return case when p->'lines'->0->>'quote_required'='true' then 'quote' else p->'lines'->0->>'price_centavos' end;
end $$;

insert into auth.users(id,email,email_confirmed_at) values
  ('00000000-0000-4000-8000-000000000731','ce-owner@example.test',now()),
  ('00000000-0000-4000-8000-000000000732','ce-staff@example.test',now()),
  ('00000000-0000-4000-8000-000000000733','ce-customer@example.test',now());
insert into herco_private.staff_memberships(user_id,role,page_grants,action_grants) values
  ('00000000-0000-4000-8000-000000000731','owner',array['Pricing'],array['changePricing']),
  ('00000000-0000-4000-8000-000000000732','staff',array['Pricing'],array['editServices']);
select set_config('test.aal','aal2',true);
update herco_private.ui_pricing set config='{
 "ceramic":{"tiers":{"1799":1799,"1999":1999,"2499":2499},"models":{"Honda Click125":1799,"Yamaha Mio":1999},
  "addons":{"Matte to Glossy":100,"Inner coating":200,"Graphene coating":300,"Mags coating":300,"Helmet coating":400,"K3 bracket / crashguard removal":500,"Decals removal":600},
  "listedAddons":{"Matte to Glossy":150,"Inner coating":250,"Graphene coating":350},"premiumGloss":5000},
 "powder":{"parts":{"Swingarm":[500,500]},"wheelRates":{"10–14 inches":[2000,2000]},"prismatic":{"10–14 inches":2500},"extras":{"Aftermarket mags":100},"largeSwingarm":[900,900]}}'::jsonb
  || jsonb_build_object('powderModel',config->'powderModel') where singleton;
insert into herco_private.services(code,label,price_centavos,enabled) values('ceramic','Ceramic coating',100000,true) on conflict (code) do update set enabled=true;
insert into herco_private.services(code,label,price_centavos,enabled) values('wheel-colour','Powder coating',100000,true) on conflict (code) do update set enabled=true;
-- A saved ceramic booking before any change.
insert into public.herco_bookings(id,customer_id,request_id,request_payload,visit_date,visit_hour,bike,customer_contact,status,original_services,original_total_centavos,created_at) values
  ('00000000-0000-4000-8000-0000000007a4','00000000-0000-4000-8000-000000000733',gen_random_uuid(),'{}',current_date+93,10,'Honda Click125','{}','pending',
   '[{"code":"ceramic","label":"Ceramic coating","price_centavos":179900}]',179900,now());

-- 1. Without any exception, ceramic prices by tier exactly as before.
set local role authenticated;
select set_config('test.uid','00000000-0000-4000-8000-000000000733',true);
do $$ begin
  perform public.herco_test_is(public.herco_test_ceramic('Honda Click125'),'179900','tier price, no exception');
  perform public.herco_test_is(public.herco_test_ceramic('Yamaha Mio'),'199900','tier price, other bike');
  perform public.herco_test_is(public.herco_test_ceramic('Unknown Bike'),'quote','a bike without a tier still quotes');
end $$;

-- 2. Owner saves ceramic exceptions: a priced one (no finish) and a quote-only one.
select set_config('test.uid','00000000-0000-4000-8000-000000000731',true);
do $$
declare cfg jsonb := public.herco_test_cfg(); r jsonb;
begin
  cfg := jsonb_set(cfg,'{powderModel,exceptions}',jsonb_build_array(public.herco_test_cex(),
    public.herco_test_cex('{"id":"00000000-0000-4000-8000-0000000007f2","bikeKey":"yamaha mio","priceCentavos":null,"quoteOnly":true}'),
    '{"id":"00000000-0000-4000-8000-0000000007f3","service":"wheel-colour","bikeKey":"honda click125","finish":"black","priceCentavos":300000,"enabled":true}'::jsonb));
  r := public.herco_save_ui_pricing(gen_random_uuid(),public.herco_test_rev(),cfg);
  if r->'config' <> cfg then raise exception 'Ceramic exceptions not saved'; end if;
  -- a ceramic exception may also carry an empty finish
  cfg := jsonb_set(cfg,'{powderModel,exceptions,0,finish}','""'::jsonb);
  perform public.herco_save_ui_pricing(gen_random_uuid(),public.herco_test_rev(),cfg);
end $$;
-- Bad ceramic exceptions are refused.
select public.herco_test_bad(jsonb_set(public.herco_test_cfg(),'{powderModel,exceptions}',jsonb_build_array(public.herco_test_cex(),public.herco_test_cex('{"id":"00000000-0000-4000-8000-0000000007f9","finish":"other"}'))));
select public.herco_test_bad(jsonb_set(public.herco_test_cfg(),'{powderModel,exceptions}',jsonb_build_array(public.herco_test_cex('{"fromFinish":"matte"}'))));
select public.herco_test_bad(jsonb_set(public.herco_test_cfg(),'{powderModel,exceptions}',jsonb_build_array(public.herco_test_cex('{"service":"bogus"}'))));
select public.herco_test_bad(jsonb_set(public.herco_test_cfg(),'{powderModel,exceptions}',jsonb_build_array(public.herco_test_cex('{"quoteOnly":true}'))));
select public.herco_test_bad(jsonb_set(public.herco_test_cfg(),'{powderModel,exceptions}',jsonb_build_array(public.herco_test_cex('{"priceCentavos":-1}'))));
select public.herco_test_bad(jsonb_set(public.herco_test_cfg(),'{powderModel,exceptions}',jsonb_build_array(public.herco_test_cex('{"bikeKey":"Honda Click125"}'))));
-- a wheel-colour exception still needs a finish
select public.herco_test_bad(jsonb_set(public.herco_test_cfg(),'{powderModel,exceptions}',jsonb_build_array(public.herco_test_cex('{"service":"wheel-colour"}'))));
select public.herco_test_bad(jsonb_set(public.herco_test_cfg(),'{powderModel,exceptions}',jsonb_build_array(public.herco_test_cex('{"service":"wheel-colour","finish":"  "}'))));

-- 3. Resolution as a customer.
select set_config('test.uid','00000000-0000-4000-8000-000000000733',true);
do $$ begin
  perform public.herco_test_is(public.herco_test_ceramic('Honda Click125'),'220000','exception price wins over the tier');
  perform public.herco_test_is(public.herco_test_ceramic('  honda CLICK125 '),'220000','bike match ignores case and spaces');
  perform public.herco_test_is(public.herco_test_ceramic('Yamaha Mio'),'quote','quote-only exception quotes');
  -- several add-ons all add up (unlisted add-ons use the add-on rate, listed ones the listed rate)
  perform public.herco_test_is(public.herco_test_ceramic('Honda Click125','["Mags coating","Helmet coating","K3 bracket / crashguard removal"]'::jsonb),'340000','three add-ons');
  perform public.herco_test_is(public.herco_test_ceramic('Honda Click125','["Inner coating","Mags coating","Matte to Glossy","Decals removal"]'::jsonb),(220000+25000+30000+15000+60000)::text,'four add-ons');
  -- a quote-only exception stays a quote with add-ons
  perform public.herco_test_is(public.herco_test_ceramic('Yamaha Mio','["Mags coating"]'::jsonb),'quote','quote line stays a quote with add-ons');
end $$;
reset role;
-- Powder pricing is unaffected by a ceramic exception on the same bike, and the ceramic exception is not used for wheels.
do $$ begin
  perform public.herco_test_is((herco_private.coating_price_lines('[{"code":"wheel-colour"}]'::jsonb,'Honda Click125',
    '{"powder_parts":["Wheels / mags"],"ui_catalog":{"wheel_type":"10-14","finish":"Black"}}'::jsonb)->0->>'price_centavos'),'300000','wheel-colour exception still applies');
  perform public.herco_test_is((herco_private.coating_price_lines('[{"code":"wheel-colour"}]'::jsonb,'Yamaha Mio',
    '{"powder_parts":["Wheels / mags"],"ui_catalog":{"wheel_type":"10-14","finish":"Black"}}'::jsonb)->0->>'price_centavos'),'219900','a ceramic exception does not price wheels');
end $$;

-- 4. Add-ons are a multi-select array in the saved options.
do $$
declare n jsonb := herco_private.normalize_coating_options(jsonb_build_object('ui_catalog',jsonb_build_object('ceramic_addons',
  jsonb_build_array('Mags coating','Helmet coating','Inner coating','Mags coating'))),array['ceramic'],'Honda Click125');
begin
  if n->'ui_catalog'->'ceramic_addons' <> '["Helmet coating","Inner coating","Mags coating"]'::jsonb then raise exception 'Add-ons not kept as a distinct list: %', n; end if;
  n := herco_private.normalize_coating_options(jsonb_build_object('ui_catalog',jsonb_build_object('ceramic_addons',
    jsonb_build_array('Matte to Glossy','Inner coating','Graphene coating','Mags coating','Helmet coating','K3 bracket / crashguard removal','Decals removal'))),array['ceramic'],'Honda Click125');
  if jsonb_array_length(n->'ui_catalog'->'ceramic_addons') <> 7 then raise exception 'All seven add-ons should be allowed'; end if;
end $$;

-- 5. A disabled exception falls back to the tier price.
update herco_private.ui_pricing set config=jsonb_set(config,'{powderModel,exceptions,0,enabled}','false'::jsonb) where singleton;
set local role authenticated;
select set_config('test.uid','00000000-0000-4000-8000-000000000733',true);
select public.herco_test_is(public.herco_test_ceramic('Honda Click125'),'179900','disabled exception falls back to the tier');
reset role;

-- 6. Permissions: staff without changePricing, a customer and a signed-out caller cannot save a ceramic exception.
set local role authenticated;
select set_config('test.uid','00000000-0000-4000-8000-000000000732',true);
select public.herco_test_refused($s$select public.herco_save_ui_pricing(gen_random_uuid(),public.herco_test_rev(),jsonb_set(public.herco_test_cfg(),'{powderModel,exceptions}',jsonb_build_array(public.herco_test_cex())))$s$,'42501');
select set_config('test.uid','00000000-0000-4000-8000-000000000733',true);
select public.herco_test_refused($s$select public.herco_save_ui_pricing(gen_random_uuid(),public.herco_test_rev(),jsonb_set(public.herco_test_cfg(),'{powderModel,exceptions}',jsonb_build_array(public.herco_test_cex())))$s$,'42501');
reset role;
set local role anon;
select set_config('test.uid','',true);
select public.herco_test_refused($s$select public.herco_save_ui_pricing(gen_random_uuid(),1,'{}')$s$,'42501');
reset role;

-- 7. The saved ceramic booking never changed through all of the above.
do $$ begin
  if not exists(select 1 from public.herco_bookings where id='00000000-0000-4000-8000-0000000007a4' and original_total_centavos=179900
    and original_services='[{"code":"ceramic","label":"Ceramic coating","price_centavos":179900}]'::jsonb) then raise exception 'A saved ceramic booking changed'; end if;
end $$;

rollback;
