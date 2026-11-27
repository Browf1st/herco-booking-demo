-- F-021 powder pricing model (migration 202611260001). Run against a fresh local or CI database after every migration.
-- Fictional data only; everything is rolled back.
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
-- Saves a changed config as the current actor and expects one SQLSTATE (default 22023).
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
-- Test-only readers, so the tests can look at the private config as any actor.
create function public.herco_test_cfg() returns jsonb language sql stable security definer set search_path='' as $$
  select config from herco_private.ui_pricing where singleton $$;
create function public.herco_test_rev() returns integer language sql stable security definer set search_path='' as $$
  select revision from herco_private.ui_pricing where singleton $$;
create function public.herco_test_color_id(color text) returns text language sql stable security definer set search_path='' as $$
  select e.value->>'id' from herco_private.ui_pricing p, jsonb_array_elements(p.config->'powderModel'->'colorEntries') e where p.singleton and e.value->>'name'=color $$;
create function public.herco_test_ex(patch jsonb default '{}') returns jsonb language sql immutable as $$
  select '{"id":"00000000-0000-4000-8000-0000000007e1","service":"wheel-colour","bikeKey":"honda pcx160","finish":"black","priceCentavos":350000,"quoteOnly":false,"enabled":true,"note":"Fixture note"}'::jsonb || patch $$;
-- Price of one wheel line as text: centavos, or 'quote'. Runs the live resolver (run as the table owner).
create function public.herco_test_price(bike text, wheel_type text, finish text, prismatic boolean default false, from_finish text default null) returns text language sql stable as $$
  select case when l->>'quote_required'='true' then 'quote' else l->>'price_centavos' end
  from (select (herco_private.coating_price_lines('[{"code":"wheel-colour","label":"Powder coating"}]'::jsonb, bike,
    jsonb_build_object('powder_parts',jsonb_build_array('Wheels / mags'),
      'ui_catalog',jsonb_strip_nulls(jsonb_build_object('wheel_type',wheel_type,'finish',finish,'prismatic',prismatic,'from_finish',from_finish))))->0) l) x $$;

insert into auth.users(id,email,email_confirmed_at) values
  ('00000000-0000-4000-8000-000000000701','pp-owner@example.test',now()),
  ('00000000-0000-4000-8000-000000000702','pp-staff@example.test',now()),
  ('00000000-0000-4000-8000-000000000703','pp-customer@example.test',now());
insert into herco_private.staff_memberships(user_id,role,page_grants,action_grants) values
  ('00000000-0000-4000-8000-000000000701','owner',array['Pricing'],array['changePricing']),
  ('00000000-0000-4000-8000-000000000702','staff',array['Pricing'],array['editServices']);
select set_config('test.aal','aal2',true);

-- 1. The migration seeded the model: decision-5 base prices, 7 Basic colours, the rest Special, Custom always quote.
do $$
declare m jsonb := (select config->'powderModel' from herco_private.ui_pricing where singleton);
begin
  if m is null or not herco_private.valid_powder_model(m) then raise exception 'powderModel missing or invalid'; end if;
  if m->'categories' <> '["basic","special","luminous-prismatic","custom"]'::jsonb then raise exception 'Categories wrong'; end if;
  if m->'baseTable'->'basic' <> '{"10-14":2199,"17":3199,"big-bike":4499,"not-sure":null}'::jsonb
    or m->'baseTable'->'special' <> '{"10-14":2499,"17":3499,"big-bike":5499,"not-sure":null}'::jsonb
    or m->'baseTable'->'luminous-prismatic' <> '{"10-14":2999,"17":3999,"big-bike":6999,"not-sure":null}'::jsonb
    or m->'baseTable'->'custom' <> '{"10-14":null,"17":null,"big-bike":null,"not-sure":null}'::jsonb then raise exception 'Base table is not the confirmed defaults'; end if;
  if (select array_agg(lower(e->>'name') order by lower(e->>'name')) from jsonb_array_elements(m->'colorEntries') e where e->>'category'='basic')
    <> array['black','crystal black','glossy black','matte black','pristine white','snow white','white'] then raise exception 'Basic colours wrong'; end if;
  if exists(select 1 from jsonb_array_elements(m->'colorEntries') e where e->>'category' not in('basic','special') or e->>'photoPath' is not null or e->'quoteOnly'<>'false'::jsonb or e->'enabled' is distinct from 'true'::jsonb)
    or not exists(select 1 from jsonb_array_elements(m->'colorEntries') e where e->>'name'='Fire Blue' and e->>'category'='special') then raise exception 'Seeded colours wrong'; end if;
  if m->'exceptions' <> '[]'::jsonb or m->'bikeTiers' <> '{}'::jsonb then raise exception 'Exceptions and tiers should start empty'; end if;
end $$;

-- Fixture config: valid ceramic and powder keys plus the seeded model (set directly, like an operator would).
update herco_private.ui_pricing set config='{
 "ceramic":{"tiers":{"1799":1799,"1999":1999,"2499":2499},"addons":{"Matte to Glossy":100,"Inner coating":100,"Graphene coating":100,"Mags coating":100,"Helmet coating":100,"K3 bracket / crashguard removal":100,"Decals removal":100},
  "listedAddons":{"Matte to Glossy":100,"Inner coating":100,"Graphene coating":100},"premiumGloss":5000},
 "powder":{"parts":{"Swingarm":[500,500]},"wheelRates":{"10–14 inches":[2000,2000]},"prismatic":{"10–14 inches":2500},"extras":{"Aftermarket mags":100},"largeSwingarm":[900,900]}}'::jsonb
  || jsonb_build_object('powderModel',config->'powderModel') where singleton;

-- A saved booking priced before any change (historical snapshot).
insert into public.herco_bookings(id,customer_id,request_id,request_payload,visit_date,visit_hour,bike,customer_contact,status,original_services,original_total_centavos,created_at) values
  ('00000000-0000-4000-8000-0000000007a1','00000000-0000-4000-8000-000000000703',gen_random_uuid(),'{}',current_date+90,10,'PP FIXTURE','{}','pending',
   '[{"code":"wheel-colour","label":"Powder coating","price_centavos":219900}]',219900,now());

-- 2. Resolution with the seeded base table only (no exceptions yet).
do $$ begin
  perform public.herco_test_is(public.herco_test_price('Yamaha Mio','10–14 inches','Black'),'219900','basic 10-14');
  perform public.herco_test_is(public.herco_test_price('Yamaha Mio','17 inches (Raider / Sniper only)','Fire Blue'),'349900','special 17');
  perform public.herco_test_is(public.herco_test_price('Yamaha Mio','Big bike / sports bike','Fire Blue'),'549900','special big bike');
  perform public.herco_test_is(public.herco_test_price('Yamaha Mio','Not sure','Black'),'quote','not sure is a quote');
  perform public.herco_test_is(public.herco_test_price('Yamaha Mio','','Black'),'quote','no size is a quote');
  perform public.herco_test_is(public.herco_test_price('Yamaha Mio','10–14 inches',''),'quote','no colour is a quote');
  perform public.herco_test_is(public.herco_test_price('Yamaha Mio','10–14 inches','Black',true),'299900','prismatic uses luminous-prismatic');
  perform public.herco_test_is(public.herco_test_price('Yamaha Mio','Big bike / sports bike','Fire Blue',true),'699900','prismatic big bike');
  perform public.herco_test_is(public.herco_test_price('Yamaha Mio','10–14 inches','Mystery Shade'),'quote','unknown colour quotes (never a fixed price)');
  perform public.herco_test_is(public.herco_test_price('Yamaha Mio','10–14 inches','  black '),'219900','colour match ignores case and spaces');
  -- Non-wheel powder parts keep pricing from config.powder.
  perform public.herco_test_is((herco_private.coating_price_lines('[{"code":"wheel-colour"}]'::jsonb,'Yamaha Mio',
    '{"powder_parts":["Swingarm"],"ui_catalog":{"wheel_type":"","finish":"Black"}}'::jsonb)->0->>'price_centavos'),'50000','swingarm unchanged');
end $$;

-- 3. Owner saves colours, a custom entry, exceptions and a bike tier. Revision +1, audit row written.
set local role authenticated;
select set_config('test.uid','00000000-0000-4000-8000-000000000701',true);
do $$
declare cfg jsonb := public.herco_test_cfg(); r jsonb; rev integer := public.herco_test_rev();
begin
  cfg := jsonb_set(cfg,'{powderModel,colorEntries}', (cfg#>'{powderModel,colorEntries}') || '[
    {"id":"00000000-0000-4000-8000-0000000007c1","name":"Two Tone Sample","category":"custom","photoPath":"entry/00000000-0000-4000-8000-0000000007c1.webp","quoteOnly":true},
    {"id":"00000000-0000-4000-8000-0000000007c2","name":"Test Per Size","category":"special","photoPath":null,"quoteOnly":false,"pricesBySize":{"10-14":2699}},
    {"id":"00000000-0000-4000-8000-0000000007c5","name":"Retired Shade","category":"luminous-prismatic","quoteOnly":false,"enabled":false},
    {"id":"00000000-0000-4000-8000-0000000007c7","name":"Retired Custom","category":"custom","quoteOnly":true,"enabled":false},
    {"id":"00000000-0000-4000-8000-0000000007c6","name":"Visible Shade","category":"luminous-prismatic","quoteOnly":false,"enabled":true}]'::jsonb);
  cfg := jsonb_set(cfg,'{powderModel,exceptions}', jsonb_build_array(
    public.herco_test_ex(),
    public.herco_test_ex('{"id":"00000000-0000-4000-8000-0000000007e2","bikeKey":"yamaha aerox","finish":"fire blue","priceCentavos":100000,"enabled":false}'),
    public.herco_test_ex('{"id":"00000000-0000-4000-8000-0000000007e3","bikeKey":"suzuki raider","finish":"matte black","priceCentavos":null,"quoteOnly":true}'),
    public.herco_test_ex('{"id":"00000000-0000-4000-8000-0000000007e4","bikeKey":"honda click125","finish":"high gloss black","fromFinish":"matte black","priceCentavos":400000}')));
  cfg := jsonb_set(cfg,'{powderModel,bikeTiers}','{"honda pcx160":"big-bike"}'::jsonb);
  r := public.herco_save_ui_pricing('00000000-0000-4000-8000-0000000007b1',rev,cfg);
  if (r->>'revision')::int <> rev+1 or r->'config' <> cfg then raise exception 'Save did not return the new revision and config: %', left(r::text,300); end if;
  -- Retry with the same request id: same answer, nothing written twice.
  if public.herco_save_ui_pricing('00000000-0000-4000-8000-0000000007b1',rev,cfg) <> r or public.herco_test_rev() <> rev+1 then raise exception 'Retry wrote again'; end if;
end $$;
-- The same request id with a different config is refused.
select public.herco_test_refused($s$select public.herco_save_ui_pricing('00000000-0000-4000-8000-0000000007b1',1,jsonb_set(public.herco_test_cfg(),'{powderModel,baseTable,basic,10-14}','2300'::jsonb))$s$,'22023');
reset role;
do $$ begin
  if (select count(*) from herco_private.ui_pricing_audit where request_id='00000000-0000-4000-8000-0000000007b1') <> 1 then raise exception 'Audit row missing or duplicated'; end if;
end $$;

-- 4. Resolution order: exception -> base -> quote.
do $$ declare black text := public.herco_test_color_id('Black'); begin
  perform public.herco_test_is(public.herco_test_price('Honda PCX160','10–14 inches','Black'),'350000','exception wins over tier and base');
  perform public.herco_test_is(public.herco_test_price('Honda PCX160','10–14 inches','BLACK'),'350000','exception match ignores case');
  perform public.herco_test_is(public.herco_test_price('Honda PCX160','Not sure',black),'350000','exception matches the colour id');
  perform public.herco_test_is(public.herco_test_price('Yamaha Mio','10–14 inches','Black'),'219900','another bike uses the base price');
  perform public.herco_test_is(public.herco_test_price('Honda PCX160','10–14 inches','Fire Blue'),'549900','bike tier beats the wheel label');
  perform public.herco_test_is(public.herco_test_price('Yamaha Aerox','10–14 inches','Fire Blue'),'249900','disabled exception falls through to base');
  perform public.herco_test_is(public.herco_test_price('Suzuki Raider','10–14 inches','Matte Black'),'quote','quote-only exception');
  perform public.herco_test_is(public.herco_test_price('Suzuki Raider','10–14 inches','Black'),'219900','quote exception is only for its colour');
  perform public.herco_test_is(public.herco_test_price('Yamaha Mio','10–14 inches','Two Tone Sample'),'quote','custom colour is a quote');
  perform public.herco_test_is(public.herco_test_price('Yamaha Mio','Big bike / sports bike','Two Tone Sample',true),'quote','custom stays a quote with prismatic');
  perform public.herco_test_is(public.herco_test_price('Yamaha Mio','10–14 inches','Test Per Size'),'269900','colour own size price');
  perform public.herco_test_is(public.herco_test_price('Yamaha Mio','17 inches (Raider / Sniper only)','Test Per Size'),'349900','other sizes inherit the category');
  perform public.herco_test_is(public.herco_test_price('Yamaha Mio','10–14 inches','Retired Shade'),'299900','disabled Luminous colour still prices as Luminous');
  perform public.herco_test_is(public.herco_test_price('Yamaha Mio','10–14 inches','Retired Custom'),'quote','disabled Custom colour still quotes');
  perform public.herco_test_is(public.herco_test_price('Yamaha Mio','10–14 inches','Visible Shade'),'299900','enabled colour uses its category');
  perform public.herco_test_is(public.herco_test_price('Honda Click125','10–14 inches','High Gloss Black'),'249900','from-finish exception needs the from-finish');
  perform public.herco_test_is(public.herco_test_price('Honda Click125','10–14 inches','High Gloss Black',false,'Matte Black'),'400000','from-finish exception matches');
  perform public.herco_test_is(public.herco_test_price('Honda Click125','10–14 inches','High Gloss Black',false,'Pearl White'),'249900','wrong from-finish falls to base');
end $$;

-- 5. Bad configs are refused (as the owner). 22023 = "Check the coating rates."
select set_config('pp.rev',public.herco_test_rev()::text,true);
set local role authenticated;
select set_config('test.uid','00000000-0000-4000-8000-000000000701',true);
-- base table
select public.herco_test_bad(jsonb_set(public.herco_test_cfg(),'{powderModel,baseTable,custom,10-14}','5000'::jsonb));
select public.herco_test_bad(jsonb_set(public.herco_test_cfg(),'{powderModel,baseTable,basic,not-sure}','3000'::jsonb));
select public.herco_test_bad(jsonb_set(public.herco_test_cfg(),'{powderModel,baseTable,basic,17}','-1'::jsonb));
select public.herco_test_bad(jsonb_set(public.herco_test_cfg(),'{powderModel,baseTable,basic,17}','10.123'::jsonb));
select public.herco_test_bad(jsonb_set(public.herco_test_cfg(),'{powderModel,baseTable,basic,17}','"abc"'::jsonb));
select public.herco_test_bad(jsonb_set(public.herco_test_cfg(),'{powderModel,baseTable,basic,17}','[5,1]'::jsonb));
select public.herco_test_bad(public.herco_test_cfg() #- '{powderModel,baseTable,basic,17}');
select public.herco_test_bad(public.herco_test_cfg() #- '{powderModel,baseTable,special}');
select public.herco_test_bad(jsonb_set(public.herco_test_cfg(),'{powderModel,categories}','["basic","special","custom"]'::jsonb));
select public.herco_test_bad(jsonb_set(public.herco_test_cfg(),'{powderModel,surprise}','1'::jsonb));
select public.herco_test_bad(public.herco_test_cfg() #- '{powderModel,exceptions}');
-- colour entries
select public.herco_test_bad(jsonb_set(public.herco_test_cfg(),'{powderModel,colorEntries,0,category}','"neon"'::jsonb));
select public.herco_test_bad(jsonb_set(public.herco_test_cfg(),'{powderModel,colorEntries,0,name}','"  "'::jsonb));
select public.herco_test_bad(jsonb_set(public.herco_test_cfg(),'{powderModel,colorEntries,0,name}',to_jsonb(repeat('x',81))));
select public.herco_test_bad(jsonb_set(public.herco_test_cfg(),'{powderModel,colorEntries,1,name}','"BLACK"'::jsonb));
select public.herco_test_bad(jsonb_set(public.herco_test_cfg(),'{powderModel,colorEntries,1,id}',public.herco_test_cfg()#>'{powderModel,colorEntries,0,id}'));
select public.herco_test_bad(jsonb_set(public.herco_test_cfg(),'{powderModel,colorEntries,1,id}','"not-a-uuid"'::jsonb));
select public.herco_test_bad(jsonb_set(public.herco_test_cfg(),'{powderModel,colorEntries,1,quoteOnly}','"yes"'::jsonb));
select public.herco_test_bad(jsonb_set(public.herco_test_cfg(),'{powderModel,colorEntries,13,quoteOnly}','false'::jsonb));
select public.herco_test_bad(jsonb_set(public.herco_test_cfg(),'{powderModel,colorEntries,13,pricesBySize}','{"10-14":1}'::jsonb));
select public.herco_test_bad(jsonb_set(public.herco_test_cfg(),'{powderModel,colorEntries,14,pricesBySize}','{"not-sure":1}'::jsonb));
select public.herco_test_bad(jsonb_set(public.herco_test_cfg(),'{powderModel,colorEntries,14,pricesBySize}','{"17":-5}'::jsonb));
select public.herco_test_bad(jsonb_set(public.herco_test_cfg(),'{powderModel,colorEntries,0,enabled}','"yes"'::jsonb));
select public.herco_test_bad(jsonb_set(public.herco_test_cfg(),'{powderModel,colorEntries,0,enabled}','null'::jsonb));
-- photo paths: absolute, parent folder, completion bucket, wrong extension, wrong id length, not a string
select public.herco_test_bad(jsonb_set(public.herco_test_cfg(),'{powderModel,colorEntries,0,photoPath}','"https://example.test/a.webp"'::jsonb));
select public.herco_test_bad(jsonb_set(public.herco_test_cfg(),'{powderModel,colorEntries,0,photoPath}','"../entry/00000000-0000-4000-8000-0000000007c1.webp"'::jsonb));
select public.herco_test_bad(jsonb_set(public.herco_test_cfg(),'{powderModel,colorEntries,0,photoPath}','"herco-completion/00000000-0000-4000-8000-0000000007c1/a.jpg"'::jsonb));
select public.herco_test_bad(jsonb_set(public.herco_test_cfg(),'{powderModel,colorEntries,0,photoPath}','"entry/00000000-0000-4000-8000-0000000007c1.gif"'::jsonb));
select public.herco_test_bad(jsonb_set(public.herco_test_cfg(),'{powderModel,colorEntries,0,photoPath}','"entry/short.webp"'::jsonb));
select public.herco_test_bad(jsonb_set(public.herco_test_cfg(),'{powderModel,colorEntries,0,photoPath}','5'::jsonb));
-- a well-formed path that belongs to another entry's id is refused
select public.herco_test_bad(jsonb_set(public.herco_test_cfg(),'{powderModel,colorEntries,0,photoPath}','"entry/00000000-0000-4000-8000-0000000007c1.webp"'::jsonb));
select public.herco_test_bad(jsonb_set(public.herco_test_cfg(),'{powderModel,colorEntries,14,photoPath}','"entry/00000000-0000-4000-8000-0000000007c1.webp"'::jsonb));
-- exceptions
select public.herco_test_bad(jsonb_set(public.herco_test_cfg(),'{powderModel,exceptions}',jsonb_build_array(public.herco_test_ex(),public.herco_test_ex('{"id":"00000000-0000-4000-8000-0000000007e9"}'))));
select public.herco_test_bad(jsonb_set(public.herco_test_cfg(),'{powderModel,exceptions}',jsonb_build_array(public.herco_test_ex(),public.herco_test_ex('{"enabled":false}'))));
select public.herco_test_bad(jsonb_set(public.herco_test_cfg(),'{powderModel,exceptions}',jsonb_build_array(public.herco_test_ex('{"quoteOnly":true}'))));
select public.herco_test_bad(jsonb_set(public.herco_test_cfg(),'{powderModel,exceptions}',jsonb_build_array(public.herco_test_ex('{"priceCentavos":null}'))));
select public.herco_test_bad(jsonb_set(public.herco_test_cfg(),'{powderModel,exceptions}',jsonb_build_array(public.herco_test_ex('{"priceCentavos":-5}'))));
select public.herco_test_bad(jsonb_set(public.herco_test_cfg(),'{powderModel,exceptions}',jsonb_build_array(public.herco_test_ex('{"priceCentavos":1.5}'))));
select public.herco_test_bad(jsonb_set(public.herco_test_cfg(),'{powderModel,exceptions}',jsonb_build_array(public.herco_test_ex('{"priceCentavos":2147483648}'))));
select public.herco_test_bad(jsonb_set(public.herco_test_cfg(),'{powderModel,exceptions}',jsonb_build_array(public.herco_test_ex('{"priceCentavos":"3500"}'))));
select public.herco_test_bad(jsonb_set(public.herco_test_cfg(),'{powderModel,exceptions}',jsonb_build_array(public.herco_test_ex('{"bikeKey":"Honda PCX160"}'))));
select public.herco_test_bad(jsonb_set(public.herco_test_cfg(),'{powderModel,exceptions}',jsonb_build_array(public.herco_test_ex('{"bikeKey":""}'))));
select public.herco_test_bad(jsonb_set(public.herco_test_cfg(),'{powderModel,exceptions}',jsonb_build_array(public.herco_test_ex('{"finish":"  "}'))));
-- an unknown service is refused ('ceramic' became valid in migration 202611260004; see ceramic-exceptions.sql)
select public.herco_test_bad(jsonb_set(public.herco_test_cfg(),'{powderModel,exceptions}',jsonb_build_array(public.herco_test_ex('{"service":"bogus"}'))));
select public.herco_test_bad(jsonb_set(public.herco_test_cfg(),'{powderModel,exceptions}',jsonb_build_array(public.herco_test_ex('{"enabled":"yes"}'))));
select public.herco_test_bad(jsonb_set(public.herco_test_cfg(),'{powderModel,exceptions}',jsonb_build_array(public.herco_test_ex(jsonb_build_object('note',repeat('x',201))))));
select public.herco_test_bad(jsonb_set(public.herco_test_cfg(),'{powderModel,exceptions}',jsonb_build_array(public.herco_test_ex('{"unknown":1}'))));
-- bike tiers, whole config
select public.herco_test_bad(jsonb_set(public.herco_test_cfg(),'{powderModel,bikeTiers}','{"honda pcx160":"huge"}'::jsonb));
select public.herco_test_bad(jsonb_set(public.herco_test_cfg(),'{powderModel,bikeTiers}','{"Honda PCX160":"17"}'::jsonb));
select public.herco_test_bad(public.herco_test_cfg() - 'ceramic');
select public.herco_test_bad('[]'::jsonb);
select public.herco_test_bad(jsonb_set(public.herco_test_cfg(),'{powder,parts,Swingarm}','-1'::jsonb));
-- stale revision
select public.herco_test_refused($s$select public.herco_save_ui_pricing(gen_random_uuid(),public.herco_test_rev()-1,public.herco_test_cfg())$s$,'40001');
reset role;
do $$ begin
  if public.herco_test_rev() <> current_setting('pp.rev')::int then raise exception 'A refused save changed the revision'; end if;
  if (select count(*) from herco_private.ui_pricing_audit) <> 1 then raise exception 'A refused save wrote an audit row'; end if;
end $$;

-- 6. Accepted edge values: free exception (0), photo extensions, a rate range, a custom entry with a null photo.
set local role authenticated;
select set_config('test.uid','00000000-0000-4000-8000-000000000701',true);
do $$
declare cfg jsonb := public.herco_test_cfg(); r jsonb;
begin
  cfg := jsonb_set(cfg,'{powderModel,exceptions}',jsonb_build_array(public.herco_test_ex('{"priceCentavos":0}')));
  cfg := jsonb_set(cfg,'{powderModel,colorEntries,0,photoPath}',to_jsonb('entry/'||(cfg#>>'{powderModel,colorEntries,0,id}')||'.jpg'));
  cfg := jsonb_set(cfg,'{powderModel,colorEntries,1,photoPath}',to_jsonb('entry/'||(cfg#>>'{powderModel,colorEntries,1,id}')||'.png'));
  cfg := jsonb_set(cfg,'{powderModel,baseTable,basic,10-14}','[2199,2399]'::jsonb);
  r := public.herco_save_ui_pricing(gen_random_uuid(),public.herco_test_rev(),cfg);
  if r->'config' <> cfg then raise exception 'Edge config not saved'; end if;
end $$;
reset role;
do $$ begin
  perform public.herco_test_is(public.herco_test_price('Honda PCX160','10–14 inches','Black'),'0','a free exception is allowed');
  perform public.herco_test_is(public.herco_test_price('Yamaha Mio','10–14 inches','White'),'219900','a range rate prices at its low end');
end $$;

-- 7. An older screen that omits powderModel keeps the stored model (nothing lost); a retry is answered.
set local role authenticated;
select set_config('test.uid','00000000-0000-4000-8000-000000000701',true);
do $$
declare before_model jsonb := public.herco_test_cfg()->'powderModel'; old_cfg jsonb := public.herco_test_cfg() - 'powderModel'; r jsonb; rev integer := public.herco_test_rev();
begin
  old_cfg := jsonb_set(old_cfg,'{powder,parts,Swingarm}','[600,600]'::jsonb);
  r := public.herco_save_ui_pricing('00000000-0000-4000-8000-0000000007b2',rev,old_cfg);
  if r->'config'->'powderModel' <> before_model or r->'config'->'powder'->'parts'->'Swingarm' <> '[600,600]'::jsonb then raise exception 'Old screen save lost the model'; end if;
  if public.herco_save_ui_pricing('00000000-0000-4000-8000-0000000007b2',rev,old_cfg) <> r or public.herco_test_rev() <> rev+1 then raise exception 'Old screen retry wrote again'; end if;
end $$;
-- Put the base price back so the next section is deterministic, and change the price for the immutability check.
do $$
declare cfg jsonb := jsonb_set(public.herco_test_cfg(),'{powderModel,baseTable,basic,10-14}','2299'::jsonb);
begin perform public.herco_save_ui_pricing(gen_random_uuid(),public.herco_test_rev(),cfg); end $$;
reset role;

-- 8. Historical snapshot is immutable; new work uses the new price.
do $$ begin
  perform public.herco_test_is(public.herco_test_price('Yamaha Mio','10–14 inches','Snow White'),'229900','new work uses the new base price');
  if not exists(select 1 from public.herco_bookings where id='00000000-0000-4000-8000-0000000007a1' and original_total_centavos=219900
    and original_services='[{"code":"wheel-colour","label":"Powder coating","price_centavos":219900}]'::jsonb) then raise exception 'A saved booking snapshot changed'; end if;
end $$;

-- 9. Permissions. canEdit follows the grant; save, swatch target are refused without changePricing, without a Pricing page,
--    for customers, signed-out callers and sessions without MFA.
set local role authenticated;
select set_config('test.uid','00000000-0000-4000-8000-000000000701',true);
do $$ begin if not (public.herco_staff_ui_pricing()->>'canEdit')::boolean then raise exception 'Owner should be able to edit'; end if; end $$;
select set_config('test.uid','00000000-0000-4000-8000-000000000702',true);
do $$ begin if (public.herco_staff_ui_pricing()->>'canEdit')::boolean then raise exception 'Staff without the grant should not edit'; end if; end $$;
select public.herco_test_refused($s$select public.herco_save_ui_pricing(gen_random_uuid(),public.herco_test_rev(),public.herco_test_cfg())$s$,'42501');
select public.herco_test_refused($s$select public.herco_pricing_swatch_target('00000000-0000-4000-8000-0000000007c1')$s$,'42501');
select set_config('test.uid','00000000-0000-4000-8000-000000000703',true);
select public.herco_test_refused($s$select public.herco_save_ui_pricing(gen_random_uuid(),public.herco_test_rev(),public.herco_test_cfg())$s$,'42501');
select public.herco_test_refused($s$select public.herco_pricing_swatch_target('00000000-0000-4000-8000-0000000007c1')$s$,'42501');
-- Pricing changes use the password_staff_access model (migration 202611190032): a verified staff session plus
-- the Pricing page and changePricing grants. MFA (aal2) is not required for pricing, so no aal1 refusal here.
reset role;
set local role anon;
select set_config('test.uid','',true);
select public.herco_test_refused($s$select public.herco_save_ui_pricing(gen_random_uuid(),1,'{}')$s$,'42501');
select public.herco_test_refused($s$select public.herco_pricing_swatch_target('00000000-0000-4000-8000-0000000007c1')$s$,'42501');
select public.herco_test_refused($s$select public.herco_booking_ui_catalog()$s$,'42501');
reset role;
do $$ begin
  if has_function_privilege('anon','public.herco_pricing_swatch_target(uuid)','execute') or has_function_privilege('public','public.herco_pricing_swatch_target(uuid)','execute')
    or has_function_privilege('anon','public.herco_save_ui_pricing(uuid,integer,jsonb)','execute')
    or has_function_privilege('authenticated','herco_private.coating_price_lines(jsonb,text,jsonb)','execute')
    or has_function_privilege('authenticated','herco_private.valid_powder_model(jsonb)','execute')
    or has_function_privilege('authenticated','herco_private.powder_wheel_rate(jsonb,text,jsonb)','execute') then raise exception 'A function is callable by the wrong role'; end if;
  if not has_function_privilege('authenticated','public.herco_pricing_swatch_target(uuid)','execute') then raise exception 'Staff cannot call the swatch target'; end if;
end $$;

-- 10. Customers read the model for pricing, without staff notes or disabled exceptions.
update herco_private.ui_pricing set config=jsonb_set(config,'{powderModel,exceptions}',jsonb_build_array(public.herco_test_ex(),
  public.herco_test_ex('{"id":"00000000-0000-4000-8000-0000000007e2","bikeKey":"yamaha aerox","finish":"fire blue","enabled":false}'))) where singleton;
set local role authenticated;
select set_config('test.uid','00000000-0000-4000-8000-000000000703',true);
do $$ declare c jsonb := public.herco_booking_ui_catalog(); ex jsonb := c->'config'->'powderModel'->'exceptions'; begin
  if c->'config'->'powderModel'->'colorEntries' is null or c->'config'->'powderModel'->'baseTable' is null then raise exception 'Customers cannot read the model'; end if;
  if exists(select 1 from jsonb_array_elements(c->'config'->'powderModel'->'colorEntries') e where e->>'name' in('Retired Shade','Retired Custom')) or not exists(select 1 from jsonb_array_elements(c->'config'->'powderModel'->'colorEntries') e where e->>'name'='Visible Shade')
    or not exists(select 1 from jsonb_array_elements(c->'config'->'powderModel'->'colorEntries') e where e->>'name'='Black') then raise exception 'Disabled colours must be hidden from customers and enabled ones kept'; end if;
  if c::text like '%Fixture note%' then raise exception 'A staff note reached customers'; end if;
  if jsonb_array_length(ex) <> 1 or ex->0->>'bikeKey' <> 'honda pcx160' or ex->0 ? 'note' then raise exception 'Customers should see only enabled exceptions, without notes: %', ex; end if;
end $$;
reset role;

-- 11. Swatch bucket: public and separate from the private completion bucket. Buckets are created outside migrations,
--     so the test creates them. The target is refused until the public bucket is correct.
set local role authenticated;
select set_config('test.uid','00000000-0000-4000-8000-000000000701',true);
select public.herco_test_refused($s$select public.herco_pricing_swatch_target('00000000-0000-4000-8000-0000000007c1')$s$,'55000');
reset role;
insert into storage.buckets(id,public,file_size_limit,allowed_mime_types) values
  ('herco-completion',false,4194304,array['image/jpeg','image/png','image/webp']),
  ('herco-swatches',true,4194304,array['image/jpeg','image/png','image/webp']);
do $$ begin
  if (select public from storage.buckets where id='herco-swatches') is not true or (select public from storage.buckets where id='herco-completion') is not false then raise exception 'Bucket visibility wrong'; end if;
  perform herco_private.require_private_completion_bucket();
  perform herco_private.require_public_swatch_bucket();
end $$;
set local role authenticated;
select set_config('test.uid','00000000-0000-4000-8000-000000000701',true);
do $$ begin
  if public.herco_pricing_swatch_target('00000000-0000-4000-8000-0000000007c1') <> 'entry/00000000-0000-4000-8000-0000000007c1' then raise exception 'Swatch target path wrong'; end if;
end $$;
select public.herco_test_refused($s$select public.herco_pricing_swatch_target('00000000-0000-4000-8000-0000000007ff')$s$,'22023');
select public.herco_test_refused($s$select public.herco_pricing_swatch_target(null)$s$,'22023');
reset role;
-- A private, resized or differently typed swatch bucket is refused.
update storage.buckets set public=false where id='herco-swatches';
set local role authenticated;
select set_config('test.uid','00000000-0000-4000-8000-000000000701',true);
select public.herco_test_refused($s$select public.herco_pricing_swatch_target('00000000-0000-4000-8000-0000000007c1')$s$,'55000');
reset role;
update storage.buckets set public=true,file_size_limit=99999999 where id='herco-swatches';
set local role authenticated;
select set_config('test.uid','00000000-0000-4000-8000-000000000701',true);
select public.herco_test_refused($s$select public.herco_pricing_swatch_target('00000000-0000-4000-8000-0000000007c1')$s$,'55000');
reset role;
update storage.buckets set file_size_limit=4194304,allowed_mime_types=array['image/jpeg','image/png','image/webp','image/svg+xml'] where id='herco-swatches';
set local role authenticated;
select set_config('test.uid','00000000-0000-4000-8000-000000000701',true);
select public.herco_test_refused($s$select public.herco_pricing_swatch_target('00000000-0000-4000-8000-0000000007c1')$s$,'55000');
reset role;
update storage.buckets set allowed_mime_types=array['image/jpeg','image/png','image/webp'] where id='herco-swatches';
-- Browser clients cannot write or remove swatch objects (restrictive policies), but other buckets and reads still work.
insert into storage.objects(bucket_id,name) values('herco-swatches','entry/fixture.webp');
set local role authenticated;
select public.herco_test_refused($s$insert into storage.objects(bucket_id,name) values('herco-swatches','entry/evil.webp')$s$,'42501');
insert into storage.objects(bucket_id,name) values('other-bucket','fixture-other');
select public.herco_test_refused($s$update storage.objects set bucket_id='herco-swatches' where name='fixture-other'$s$,'42501');
do $$ begin
  update storage.objects set name='entry/renamed.webp' where bucket_id='herco-swatches';
  delete from storage.objects where bucket_id='herco-swatches';
  if (select count(*) from storage.objects where bucket_id='herco-swatches' and name='entry/fixture.webp') <> 1 then raise exception 'Browser client changed a swatch object'; end if;
end $$;
reset role;

rollback;
