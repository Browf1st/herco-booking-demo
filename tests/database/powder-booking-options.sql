-- F-022 server step (migration 202611260003): the powder booking screen's options are accepted and priced from the colour list.
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
-- Customer preview of one powder wheel line: 'quote' or centavos. ui is the ui_catalog object.
create function public.herco_test_preview(bike text, ui jsonb) returns text language plpgsql stable as $$
declare p jsonb := public.herco_preview_coating_price(bike,array['wheel-colour'],
  jsonb_build_object('powder_parts',jsonb_build_array('Wheels / mags'),'wheel_front','Not sure','ui_catalog',ui));
begin
  return case when p->'lines'->0->>'quote_required'='true' then 'quote' else p->'lines'->0->>'price_centavos' end;
end $$;
create function public.herco_test_is(actual text, expected text, label text) returns void language plpgsql as $$
begin
  if actual is distinct from expected then raise exception '% expected % but got %', label, expected, actual; end if;
end $$;

insert into auth.users(id,email,email_confirmed_at) values('00000000-0000-4000-8000-000000000721','pb-customer@example.test',now());
update herco_private.ui_pricing set config='{
 "ceramic":{"tiers":{"1799":1799,"1999":1999,"2499":2499},"addons":{"Matte to Glossy":100,"Inner coating":100,"Graphene coating":100,"Mags coating":100,"Helmet coating":100,"K3 bracket / crashguard removal":100,"Decals removal":100},
  "listedAddons":{"Matte to Glossy":100,"Inner coating":100,"Graphene coating":100},"premiumGloss":5000},
 "powder":{"parts":{"Swingarm":[500,500]},"wheelRates":{"10–14 inches":[2000,2000]},"prismatic":{"10–14 inches":2500},"extras":{"Aftermarket mags":100},"largeSwingarm":[900,900]}}'::jsonb
  || jsonb_build_object('powderModel',jsonb_set(config->'powderModel','{colorEntries}',(config->'powderModel'->'colorEntries')||
   '[{"id":"00000000-0000-4000-8000-0000000007d1","name":"Two Tone Sample","category":"custom","quoteOnly":true,"photoPath":null},
     {"id":"00000000-0000-4000-8000-0000000007d2","name":"Glow Sample","category":"luminous-prismatic","quoteOnly":false,"photoPath":null}]'::jsonb)) where singleton;
insert into herco_private.services(code,label,price_centavos,enabled) values('wheel-colour','Powder coating',100000,true) on conflict (code) do update set enabled=true;
-- A saved booking made before any of this (historical snapshot).
insert into public.herco_bookings(id,customer_id,request_id,request_payload,visit_date,visit_hour,bike,customer_contact,status,original_services,original_total_centavos,created_at) values
  ('00000000-0000-4000-8000-0000000007a3','00000000-0000-4000-8000-000000000721',gen_random_uuid(),'{}',current_date+92,10,'PB FIXTURE','{}','pending',
   '[{"code":"wheel-colour","label":"Powder coating","price_centavos":219900}]',219900,now());
select set_config('pb.id',(select e->>'id' from herco_private.ui_pricing p,jsonb_array_elements(p.config->'powderModel'->'colorEntries') e where p.singleton and e->>'name'='Fire Blue'),true);
select set_config('pb.black',(select e->>'id' from herco_private.ui_pricing p,jsonb_array_elements(p.config->'powderModel'->'colorEntries') e where p.singleton and e->>'name'='Black'),true);

set local role authenticated;
select set_config('test.uid','00000000-0000-4000-8000-000000000721',true);
do $$ declare fire text := current_setting('pb.id'); begin
  -- (a) size key + category + colour id + note: priced by the colour's own category (special, 15-17 in)
  perform public.herco_test_is(public.herco_test_preview('Yamaha Mio',jsonb_build_object('wheel_type','17','finish','Fire Blue','powder_category','special','color_id',fire,'custom_note','  hello  ')),'349900','size key 17 special');
  -- (b) any bike can book 15-17 in, with or without the old Raider/Sniper flag
  perform public.herco_test_is(public.herco_test_preview('Honda Click125',jsonb_build_object('wheel_type','17','finish','Fire Blue')),'349900','non-Raider 17');
  perform public.herco_test_is(public.herco_test_preview('Honda Click125',jsonb_build_object('wheel_type','17','finish','Fire Blue','raider_sniper_confirmed',false)),'349900','old flag ignored');
  perform public.herco_test_is(public.herco_test_preview('Honda Click125',jsonb_build_object('wheel_type','17 inches (Raider / Sniper only)','finish','Fire Blue','raider_sniper_confirmed',true)),'349900','old label still works');
  -- (c) custom category quotes
  perform public.herco_test_is(public.herco_test_preview('Yamaha Mio',jsonb_build_object('wheel_type','17','finish','Two Tone Sample','powder_category','custom','color_id','00000000-0000-4000-8000-0000000007d1','custom_note','Two tone red and black')),'quote','custom is a quote');
  -- (d) other size keys
  perform public.herco_test_is(public.herco_test_preview('Yamaha Mio',jsonb_build_object('wheel_type','big-bike','finish','Fire Blue')),'549900','big-bike');
  perform public.herco_test_is(public.herco_test_preview('Yamaha Mio',jsonb_build_object('wheel_type','10-14','finish','Black')),'219900','10-14');
  perform public.herco_test_is(public.herco_test_preview('Yamaha Mio',jsonb_build_object('wheel_type','not-sure','finish','Black')),'quote','not-sure quotes');
  -- The colour id alone is enough; the customer's own category claim never changes the price.
  perform public.herco_test_is(public.herco_test_preview('Yamaha Mio',jsonb_build_object('wheel_type','17','color_id',fire)),'349900','colour id without finish text');
  perform public.herco_test_is(public.herco_test_preview('Yamaha Mio',jsonb_build_object('wheel_type','17','finish','Fire Blue','powder_category','basic')),'349900','category claim is not trusted');
  perform public.herco_test_is(public.herco_test_preview('Yamaha Mio',jsonb_build_object('wheel_type','17','finish','Glow Sample','powder_category','basic')),'399900','luminous colour keeps its category');
  perform public.herco_test_is(public.herco_test_preview('Yamaha Mio',jsonb_build_object('wheel_type','17','finish','Nobody Knows Shade')),'quote','unknown finish quotes');
  perform public.herco_test_is(public.herco_test_preview('Yamaha Mio',jsonb_build_object('wheel_type','17','finish','Black','color_id','00000000-0000-4000-8000-0000000007d1')),'quote','colour id wins over a different finish name');
  -- from_finish is accepted (even empty) and old shapes still work
  perform public.herco_test_is(public.herco_test_preview('Yamaha Mio',jsonb_build_object('wheel_type','17','finish','Fire Blue','from_finish','')),'349900','empty from_finish');
  perform public.herco_test_is(public.herco_test_preview('Yamaha Mio',jsonb_build_object('wheel_type','10–14 inches','finish','Black')),'219900','old label shape');
end $$;
-- Genuinely bad values are still refused (22023).
select public.herco_test_refused($s$select public.herco_test_preview('Yamaha Mio','{"wheel_type":"17","finish":"Black","evil_key":1}'::jsonb)$s$,'22023');
select public.herco_test_refused($s$select public.herco_test_preview('Yamaha Mio','{"wheel_type":"20","finish":"Black"}'::jsonb)$s$,'22023');
select public.herco_test_refused($s$select public.herco_test_preview('Yamaha Mio','{"wheel_type":"17","finish":"Black","powder_category":"neon"}'::jsonb)$s$,'22023');
select public.herco_test_refused($s$select public.herco_test_preview('Yamaha Mio','{"wheel_type":"17","finish":"Black","color_id":"not-a-uuid"}'::jsonb)$s$,'22023');
select public.herco_test_refused($s$select public.herco_test_preview('Yamaha Mio','{"wheel_type":"17","finish":"Black","custom_note":5}'::jsonb)$s$,'22023');
select public.herco_test_refused($s$select public.herco_test_preview('Yamaha Mio','{"wheel_type":"17","finish":"Black","raider_sniper_confirmed":"yes"}'::jsonb)$s$,'22023');
select public.herco_test_refused($s$select public.herco_test_preview('Yamaha Mio',jsonb_build_object('wheel_type','17','finish','Black','from_finish',repeat('x',101)))$s$,'22023');
reset role;

-- The normalized snapshot keeps the new keys; the note is trimmed and cut to 300; old shapes are unchanged.
do $$
declare n jsonb;
begin
  n := herco_private.normalize_coating_options(jsonb_build_object('powder_parts',jsonb_build_array('Wheels / mags'),'wheel_front','Not sure','raider_sniper_confirmed',true,
    'ui_catalog',jsonb_build_object('wheel_type','17','finish',' Two Tone Sample ','powder_category','custom','color_id',upper('00000000-0000-4000-8000-0000000007d1'),
      'custom_note','  '||repeat('n',400),'from_finish','  Matte  ','raider_sniper_confirmed',true)),array['wheel-colour'],'Honda Click125');
  if n->'ui_catalog'->>'wheel_type'<>'17' or n->'ui_catalog'->>'powder_category'<>'custom' or n->'ui_catalog'->>'color_id'<>'00000000-0000-4000-8000-0000000007d1'
    or char_length(n->'ui_catalog'->>'custom_note')<>300 or n->'ui_catalog'->>'from_finish'<>'Matte' or n->'ui_catalog'->>'finish'<>'Two Tone Sample' then raise exception 'Normalized options wrong: %', n; end if;
  if n::text like '%raider_sniper%' then raise exception 'The ignored flag was stored'; end if;
  n := herco_private.normalize_coating_options(jsonb_build_object('powder_parts',jsonb_build_array('Wheels / mags'),'wheel_front','Not sure',
    'ui_catalog',jsonb_build_object('wheel_type','10–14 inches','finish','Black')),array['wheel-colour'],'Yamaha Mio');
  if n->'ui_catalog' ? 'powder_category' or n->'ui_catalog' ? 'color_id' or n->'ui_catalog' ? 'custom_note' or n->'ui_catalog' ? 'from_finish' then raise exception 'Old shape gained keys: %', n; end if;
  if (select (herco_private.coating_price_lines('[{"code":"wheel-colour"}]'::jsonb,'Honda Click125',
      jsonb_build_object('powder_parts',jsonb_build_array('Wheels / mags'),'ui_catalog',jsonb_build_object('wheel_type','17','finish','Two Tone Sample','custom_note','x')))->0->>'quote_required')) <> 'true' then raise exception 'Custom should quote'; end if;
end $$;

-- A saved booking is untouched.
do $$ begin
  if not exists(select 1 from public.herco_bookings where id='00000000-0000-4000-8000-0000000007a3' and original_total_centavos=219900
    and original_services='[{"code":"wheel-colour","label":"Powder coating","price_centavos":219900}]'::jsonb) then raise exception 'A saved booking changed'; end if;
end $$;

rollback;
