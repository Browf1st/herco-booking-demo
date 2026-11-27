-- F-022 server step: let the powder booking screen's options through, and price from the colour list.
-- OWNER-AUTHORIZED HOSTED RELEASE STEP: apply after 202611260001 and 202611260002, together with the Worker.
-- Additive: old option shapes and old saved bookings keep working. Saved booking snapshots are never rewritten.
-- Raider/Sniper: no server function named supports_seventeen_inch_mags or reading raider_sniper_confirmed existed;
-- the only server limits were the wheel_type allow-list and the unknown-key check, both relaxed here. The size
-- '17' (15-17 in) is open to every bike. raider_sniper_confirmed is accepted and ignored (never stored).
begin;

create or replace function herco_private.normalize_coating_options(options jsonb,service_codes text[],bike text)
returns jsonb language plpgsql immutable set search_path='' as $$
declare normalized jsonb; c jsonb; k text; value text; result jsonb; note text;
begin
 normalized:=herco_private.normalize_coating_options_legacy(options-'ui_catalog'-'raider_sniper_confirmed',service_codes,bike);
 if not options?'ui_catalog' then return normalized; end if;
 c:=options->'ui_catalog';
 if jsonb_typeof(c)<>'object' or octet_length(c::text)>4000 or exists(select 1 from jsonb_object_keys(c) x where x not in
 ('ceramic_addons','wheel_type','prismatic','wheel_extras','big_bike','other_big_bike','finish','model_year','notes',
  'powder_category','color_id','custom_note','from_finish','raider_sniper_confirmed')) then
  raise exception 'Check your service options.' using errcode='22023'; end if;
 foreach k in array array['ceramic_addons','wheel_extras'] loop
  if c?k and (jsonb_typeof(c->k)<>'array' or jsonb_array_length(c->k)>12) then raise exception 'Check your selected add-ons.' using errcode='22023'; end if;
  for value in select jsonb_array_elements_text(coalesce(c->k,'[]')) loop
   if (k='ceramic_addons' and value not in('Matte to Glossy','Inner coating','Graphene coating','Mags coating','Helmet coating','K3 bracket / crashguard removal','Decals removal'))
    or (k='wheel_extras' and value not in('Aftermarket mags','Previously powder-coated mags','Protective top coat')) then
    raise exception 'Choose valid add-ons.' using errcode='22023'; end if;
  end loop;
 end loop;
 foreach k in array array['prismatic','big_bike','other_big_bike','raider_sniper_confirmed'] loop
  if c?k and jsonb_typeof(c->k)<>'boolean' then raise exception 'Check your motorcycle options.' using errcode='22023'; end if;
 end loop;
 if char_length(coalesce(c->>'notes',''))>700 or char_length(coalesce(c->>'finish',''))>100
  or (c?'model_year' and (jsonb_typeof(c->'model_year')<>'number' or (c->>'model_year')!~'^\d{4}$' or (c->>'model_year')::integer not between 1980 and 2100))
  or coalesce(c->>'wheel_type','') not in('','10–14 inches','17 inches (Raider / Sniper only)','Big bike / sports bike','Not sure','10-14','17','big-bike','not-sure') then
  raise exception 'Check the motorcycle year, notes and wheel configuration.' using errcode='22023'; end if;
 foreach k in array array['powder_category','color_id','custom_note','from_finish'] loop
  if c?k and jsonb_typeof(c->k)<>'string' then raise exception 'Check your powder colour options.' using errcode='22023'; end if;
 end loop;
 if coalesce(c->>'powder_category','') not in('','basic','special','luminous-prismatic','custom')
  or (coalesce(c->>'color_id','')<>'' and (c->>'color_id') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
  or char_length(btrim(coalesce(c->>'from_finish','')))>100 then
  raise exception 'Check your powder colour options.' using errcode='22023'; end if;
 if not('ceramic'=any(service_codes)) and jsonb_array_length(coalesce(c->'ceramic_addons','[]'))>0 then raise exception 'Ceramic add-ons require ceramic coating.' using errcode='22023'; end if;
 if not('wheel-colour'=any(service_codes)) and (coalesce(c->>'finish','')<>'' or coalesce(c->>'wheel_type','')<>'' or jsonb_array_length(coalesce(c->'wheel_extras','[]'))>0 or c->'prismatic'='true') then raise exception 'Powder options require powder coating.' using errcode='22023'; end if;
 if coalesce(c->>'wheel_type','')<>'' and not(coalesce(normalized->'powder_parts','[]')?'Wheels / mags') then raise exception 'Choose mags before a wheel category.' using errcode='22023'; end if;
 result:=jsonb_build_object('ceramic_addons',(select coalesce(jsonb_agg(v order by v),'[]') from(select distinct jsonb_array_elements_text(coalesce(c->'ceramic_addons','[]')) v)s),
 'wheel_type',coalesce(c->>'wheel_type',''),'prismatic',coalesce(c->'prismatic','false'),'wheel_extras',(select coalesce(jsonb_agg(v order by v),'[]') from(select distinct jsonb_array_elements_text(coalesce(c->'wheel_extras','[]')) v)s),
 'big_bike',coalesce(c->'big_bike','false'),'other_big_bike',coalesce(c->'other_big_bike','false'),'finish',btrim(coalesce(c->>'finish','')),'notes',btrim(coalesce(c->>'notes','')));
 if c?'model_year' then result:=result||jsonb_build_object('model_year',(c->>'model_year')::integer); end if;
 -- New keys are stored only when sent, so older request shapes normalize exactly as before.
 if c?'powder_category' then result:=result||jsonb_build_object('powder_category',c->>'powder_category'); end if;
 if c?'color_id' then result:=result||jsonb_build_object('color_id',lower(c->>'color_id')); end if;
 if c?'from_finish' then result:=result||jsonb_build_object('from_finish',btrim(c->>'from_finish')); end if;
 if c?'custom_note' then
  note:=left(btrim(regexp_replace(c->>'custom_note','[\x01-\x08\x0B\x0C\x0E-\x1F\x7F]','','g')),300);
  result:=result||jsonb_build_object('custom_note',note);
 end if;
 return normalized||jsonb_build_object('ui_catalog',result);
end $$;
revoke all on function herco_private.normalize_coating_options(jsonb,text[],text) from public,anon,authenticated;

-- Same resolution as before (exception -> colour/category base -> quote). Now the colour can be named by
-- color_id (used when sent and known) or by the finish name. The customer's powder_category is never trusted:
-- the category always comes from the saved colour entry.
create or replace function herco_private.powder_wheel_rate(config jsonb, bike text, c jsonb)
returns jsonb language plpgsql stable set search_path='' as $$
declare m jsonb:=config->'powderModel'; wt text:=coalesce(c->>'wheel_type',''); bk text:=lower(btrim(coalesce(bike,'')));
 cid text:=lower(btrim(coalesce(c->>'color_id','')));
 finish text:=lower(btrim(coalesce(c->>'finish',''))); sz text; cat text; entry jsonb; ex jsonb; rate jsonb;
begin
 if finish='' and cid='' then return null; end if; -- no colour chosen yet: the shop quotes
 sz:=m->'bikeTiers'->>bk;
 if sz is null then
  sz:=case wt when '10–14 inches' then '10-14' when '17 inches (Raider / Sniper only)' then '17' when 'Big bike / sports bike' then 'big-bike'
   when '10-14' then '10-14' when '17' then '17' when 'big-bike' then 'big-bike' else 'not-sure' end;
 end if;
 if cid<>'' then
  select e.value into entry from jsonb_array_elements(coalesce(m->'colorEntries','[]')) e where lower(e.value->>'id')=cid limit 1;
 end if;
 if entry is null and finish<>'' then
  -- enabled only hides a colour from customers; it never changes its price
  select e.value into entry from jsonb_array_elements(coalesce(m->'colorEntries','[]')) e where lower(e.value->>'id')=finish or lower(btrim(e.value->>'name'))=finish limit 1;
 end if;
 if entry is not null and finish='' then finish:=lower(btrim(entry->>'name')); end if;
 cat:=entry->>'category'; -- null when no colour matches: the shop quotes (after any exception below)
 select x.value into ex from jsonb_array_elements(coalesce(m->'exceptions','[]')) x
 where coalesce((x.value->>'enabled')::boolean,false) and coalesce(x.value->>'service','wheel-colour')='wheel-colour' and x.value->>'bikeKey'=bk
  and lower(btrim(x.value->>'finish'))=any(array[finish,lower(coalesce(entry->>'id','')),lower(btrim(coalesce(entry->>'name','')))])
  and (x.value->>'fromFinish' is null or lower(btrim(x.value->>'fromFinish'))=lower(btrim(coalesce(c->>'from_finish',''))))
 order by (x.value->>'fromFinish' is not null) desc limit 1;
 if found then
  if ex->>'quoteOnly'='true' or ex->>'priceCentavos' is null then return null; end if;
  return to_jsonb(round((ex->>'priceCentavos')::numeric/100,2));
 end if;
 if entry is null or cat='custom' or sz='not-sure' or entry->>'quoteOnly'='true' then return null; end if;
 if c->'prismatic'='true' then cat:='luminous-prismatic'; end if;
 rate:=coalesce(nullif(entry->'pricesBySize'->sz,'null'::jsonb),m->'baseTable'->cat->sz);
 return nullif(rate,'null'::jsonb);
end $$;
revoke all on function herco_private.powder_wheel_rate(jsonb,text,jsonb) from public,anon,authenticated;

notify pgrst,'reload schema';
commit;
