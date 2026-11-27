-- F-023 database step: staff per-bike ceramic prices reuse the F-021 exceptions list (service 'ceramic').
-- OWNER-AUTHORIZED HOSTED RELEASE STEP: apply after 202611260001-0003, together with the Worker.
-- Additive: with no ceramic exception, ceramic prices exactly as before (config.ceramic tiers and add-ons).
-- Saved booking snapshots are never rewritten; this only changes how new or edited work is priced.
begin;

-- Staff price for one bike's ceramic line. SQL null = no exception; json null = quote; a number = pesos.
create function herco_private.ceramic_exception_rate(config jsonb, bike text)
returns jsonb language plpgsql stable set search_path='' as $$
declare ex jsonb;
begin
 select x.value into ex from jsonb_array_elements(coalesce(config->'powderModel'->'exceptions','[]')) x
 where coalesce((x.value->>'enabled')::boolean,false) and x.value->>'service'='ceramic' and x.value->>'bikeKey'=lower(btrim(coalesce(bike,''))) limit 1;
 if not found then return null; end if;
 if ex->>'quoteOnly'='true' or ex->>'priceCentavos' is null then return 'null'::jsonb; end if;
 return to_jsonb(round((ex->>'priceCentavos')::numeric/100,2));
end $$;
revoke all on function herco_private.ceramic_exception_rate(jsonb,text) from public,anon,authenticated;

-- Same checks as before; an exception's service may now also be 'ceramic' (finish optional, no from-finish,
-- one exception per bike).
create or replace function herco_private.valid_powder_model(model jsonb)
returns boolean language plpgsql immutable set search_path='' as $$
declare cats constant text[]:=array['basic','special','luminous-prismatic','custom'];
 sizes constant text[]:=array['10-14','17','big-bike','not-sure'];
 uuid_pattern constant text:='^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';
 cat text; sz text; cell jsonb; r jsonb; entry jsonb; ex jsonb; k text; v jsonb; ids text[]:='{}'; names text[]:='{}'; sigs text[]:='{}'; sig text; has_price boolean; is_quote boolean;
begin
 if coalesce(jsonb_typeof(model),'')<>'object' or not coalesce(model ?& array['categories','baseTable','colorEntries','exceptions','bikeTiers'],false)
  or (select count(*) from jsonb_object_keys(model))<>5 then return false; end if;
 if model->'categories' is distinct from to_jsonb(cats) then return false; end if;
 -- Base table: 4 categories x 4 sizes; Custom and Not sure are always quote (null).
 if coalesce(jsonb_typeof(model->'baseTable'),'')<>'object' or (select count(*) from jsonb_object_keys(model->'baseTable'))<>4
  or not coalesce(model->'baseTable' ?& cats,false) then return false; end if;
 foreach cat in array cats loop
  r:=model->'baseTable'->cat;
  if coalesce(jsonb_typeof(r),'')<>'object' or (select count(*) from jsonb_object_keys(r))<>4 or not coalesce(r ?& sizes,false) then return false; end if;
  foreach sz in array sizes loop
   cell:=r->sz;
   if jsonb_typeof(cell)='null' then continue; end if;
   if cat='custom' or sz='not-sure' or jsonb_typeof(cell) not in('number','array') or not herco_private.valid_price_tree(cell) then return false; end if;
  end loop;
 end loop;
 -- Colour entries.
 if coalesce(jsonb_typeof(model->'colorEntries'),'')<>'array' or jsonb_array_length(model->'colorEntries')>300 then return false; end if;
 for entry in select e.value from jsonb_array_elements(model->'colorEntries') e loop
  if jsonb_typeof(entry)<>'object' or exists(select 1 from jsonb_object_keys(entry) x where x<>all(array['id','name','category','photoPath','quoteOnly','pricesBySize','enabled']))
   or not coalesce(entry ?& array['id','name','category','quoteOnly'],false) then return false; end if;
  if jsonb_typeof(entry->'id')<>'string' or entry->>'id' !~ uuid_pattern or (entry->>'id')=any(ids) then return false; end if;
  ids:=ids||(entry->>'id');
  if jsonb_typeof(entry->'name')<>'string' or char_length(btrim(entry->>'name')) not between 1 and 80 or lower(btrim(entry->>'name'))=any(names) then return false; end if;
  names:=names||lower(btrim(entry->>'name'));
  if jsonb_typeof(entry->'category')<>'string' or not ((entry->>'category')=any(cats)) or jsonb_typeof(entry->'quoteOnly')<>'boolean' then return false; end if;
  if entry ? 'photoPath' and jsonb_typeof(entry->'photoPath')<>'null'
   and (jsonb_typeof(entry->'photoPath')<>'string' or char_length(entry->>'photoPath')>200 or entry->>'photoPath' !~ ('^entry/'||(entry->>'id')||'\.(webp|jpg|png)$')) then return false; end if;
  if entry ? 'enabled' and jsonb_typeof(entry->'enabled')<>'boolean' then return false; end if;
  if entry ? 'pricesBySize' then
   if jsonb_typeof(entry->'pricesBySize')<>'object' then return false; end if;
   for k,v in select p.key,p.value from jsonb_each(entry->'pricesBySize') p loop
    if k<>all(array['10-14','17','big-bike']) or jsonb_typeof(v) not in('number','array') or not herco_private.valid_price_tree(v) then return false; end if;
   end loop;
  end if;
  if entry->>'category'='custom' and (entry->'quoteOnly'<>'true'::jsonb or entry ? 'pricesBySize') then return false; end if;
 end loop;
 -- Exceptions: one fixed price or quote-only, no duplicates.
 if coalesce(jsonb_typeof(model->'exceptions'),'')<>'array' or jsonb_array_length(model->'exceptions')>500 then return false; end if;
 ids:='{}';
 for ex in select e.value from jsonb_array_elements(model->'exceptions') e loop
  if jsonb_typeof(ex)<>'object' or exists(select 1 from jsonb_object_keys(ex) x where x<>all(array['id','service','bikeKey','finish','fromFinish','priceCentavos','quoteOnly','enabled','note']))
   or not coalesce(ex ?& array['id','bikeKey','enabled'],false) then return false; end if;
  if jsonb_typeof(ex->'id')<>'string' or ex->>'id' !~ uuid_pattern or (ex->>'id')=any(ids) then return false; end if;
  ids:=ids||(ex->>'id');
  if ex ? 'service' and (jsonb_typeof(ex->'service')<>'string' or ex->>'service' not in('wheel-colour','ceramic')) then return false; end if;
  if coalesce(ex->>'service','wheel-colour')<>'ceramic' and not (ex ? 'finish') then return false; end if;
  if jsonb_typeof(ex->'bikeKey')<>'string' or char_length(ex->>'bikeKey') not between 1 and 120 or ex->>'bikeKey'<>lower(btrim(ex->>'bikeKey')) then return false; end if;
  if coalesce(ex->>'service','wheel-colour')='ceramic' then
   -- ceramic has no colour: finish may be empty or absent, and there is no from-finish
   if ex ? 'finish' and (jsonb_typeof(ex->'finish')<>'string' or char_length(btrim(ex->>'finish'))>100) then return false; end if;
   if ex ? 'fromFinish' and jsonb_typeof(ex->'fromFinish')<>'null' then return false; end if;
  elsif jsonb_typeof(ex->'finish')<>'string' or char_length(btrim(ex->>'finish')) not between 1 and 100 then return false; end if;
  if ex ? 'fromFinish' and jsonb_typeof(ex->'fromFinish')<>'null' and (jsonb_typeof(ex->'fromFinish')<>'string' or char_length(btrim(ex->>'fromFinish')) not between 1 and 100) then return false; end if;
  if jsonb_typeof(ex->'enabled')<>'boolean' then return false; end if;
  if ex ? 'note' and (jsonb_typeof(ex->'note')<>'string' or char_length(ex->>'note')>200) then return false; end if;
  if ex ? 'quoteOnly' and jsonb_typeof(ex->'quoteOnly')<>'boolean' then return false; end if;
  has_price:=ex ? 'priceCentavos' and jsonb_typeof(ex->'priceCentavos')<>'null';
  is_quote:=coalesce(ex->'quoteOnly'='true'::jsonb,false);
  if has_price=is_quote then return false; end if;
  if has_price then
   if jsonb_typeof(ex->'priceCentavos')<>'number' or (ex->>'priceCentavos') !~ '^[0-9]{1,10}$' then return false; end if;
   if (ex->>'priceCentavos')::bigint>2147483647 then return false; end if;
  end if;
  sig:=case when coalesce(ex->>'service','wheel-colour')='ceramic' then 'ceramic|'||(ex->>'bikeKey') else coalesce(ex->>'service','wheel-colour')||'|'||(ex->>'bikeKey')||'|'||lower(btrim(ex->>'finish'))||'|'||lower(btrim(coalesce(ex->>'fromFinish',''))) end;
  if sig=any(sigs) then return false; end if;
  sigs:=sigs||sig;
 end loop;
 -- Bike tiers.
 if coalesce(jsonb_typeof(model->'bikeTiers'),'')<>'object' or (select count(*) from jsonb_object_keys(model->'bikeTiers'))>500 then return false; end if;
 for k,v in select t.key,t.value from jsonb_each(model->'bikeTiers') t loop
  if char_length(k) not between 1 and 120 or k<>lower(btrim(k)) or jsonb_typeof(v)<>'string' or not ((v#>>'{}')=any(sizes)) then return false; end if;
 end loop;
 return true;
exception when others then return false;
end $$;
revoke all on function herco_private.valid_powder_model(jsonb) from public,anon,authenticated;

-- Same output and add-on pricing as before; only the ceramic base price checks for a staff exception first.
create or replace function herco_private.coating_price_lines(base_lines jsonb,bike text,options jsonb)
returns jsonb language plpgsql stable set search_path='' as $$
declare cex jsonb; config jsonb; c jsonb:=options->'ui_catalog'; line jsonb; detail jsonb; details jsonb; result jsonb:='[]'; promo herco_private.booking_promotion; tier text; part text; rate jsonb; amount bigint; maximum bigint; quoted boolean;
begin
 if c is null then return herco_private.coating_price_lines_legacy(base_lines,bike,options); end if;
 select p.config into config from herco_private.ui_pricing p where singleton;
 select p.* into promo from herco_private.booking_promotion p where p.singleton and p.enabled;
 tier:=case when c->'other_big_bike'='true' then '2499' else config->'ceramic'->'models'->>bike end;
 if tier is null and c->'big_bike'='true' then tier:='2499'; end if;
 for line in select value from jsonb_array_elements(base_lines) loop
  details:='[]';
  if line->>'code'='ceramic' then
   cex:=herco_private.ceramic_exception_rate(config,bike); -- staff per-bike price first (null = none; json null = quote), else the tier price as before
   details:=jsonb_build_array(herco_private.ui_component_price('ceramic','Ceramic coating',case when cex is null then config->'ceramic'->'tiers'->tier else cex end,promo));
   for part in select jsonb_array_elements_text(c->'ceramic_addons') loop
    rate:=case when part='Matte to Glossy' and (tier='2499' or (bike~*'^Honda PCX' and c->>'model_year'='2026')) then config->'ceramic'->'premiumGloss'
      when tier is not null and config->'ceramic'->'listedAddons'?part then config->'ceramic'->'listedAddons'->part else config->'ceramic'->'addons'->part end;
    details:=details||jsonb_build_array(herco_private.ui_component_price('ceramic-addon-'||part,part,rate,promo));
   end loop;
  elsif line->>'code'='wheel-colour' then
   for part in select jsonb_array_elements_text(coalesce(options->'powder_parts','[]')) loop
    if part='Wheels / mags' then
     rate:=case when config ? 'powderModel' then herco_private.powder_wheel_rate(config,bike,c)
      when c->'prismatic'='true' then config->'powder'->'prismatic'->(c->>'wheel_type') else config->'powder'->'wheelRates'->(c->>'wheel_type') end;
    else rate:=case when part='Swingarm' and (c->'big_bike'='true' or bike~*'Raider|Sniper') then config->'powder'->'largeSwingarm' else config->'powder'->'parts'->part end; end if;
    details:=details||jsonb_build_array(herco_private.ui_component_price('powder-'||part,part||case when part='Wheels / mags' then ' · '||coalesce(c->>'wheel_type','Not sure') else '' end||case when c->>'finish'<>'' then ' · '||(c->>'finish') else '' end,rate,promo));
   end loop;
   for part in select jsonb_array_elements_text(c->'wheel_extras') loop details:=details||jsonb_build_array(herco_private.ui_component_price('powder-extra-'||part,part,config->'powder'->'extras'->part,promo));end loop;
   if details='[]' then details:=jsonb_build_array(herco_private.ui_component_price('wheel-colour','Powder coating',null,promo));end if;
  else result:=result||jsonb_build_array(line);continue;end if;
  select sum((x->>'price_centavos')::bigint),sum(coalesce((x->>'max_centavos')::bigint,(x->>'price_centavos')::bigint)),bool_or(coalesce((x->>'quote_required')::boolean,false)) into amount,maximum,quoted from jsonb_array_elements(details)x;
  result:=result||jsonb_build_array(jsonb_strip_nulls((line-array['price_centavos','max_centavos','quote_required','promotion'])||jsonb_build_object('price_centavos',amount,'max_centavos',case when maximum>amount then maximum end,'quote_required',case when quoted then true end,'details',details)));
 end loop;
 return result;
end $$;
revoke all on function herco_private.coating_price_lines(jsonb,text,jsonb) from public,anon,authenticated;

notify pgrst,'reload schema';
commit;
