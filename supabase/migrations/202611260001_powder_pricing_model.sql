-- F-021 step 1: powder pricing model (base table + colour entries + exceptions) in herco_private.ui_pricing.
-- Additive: config keys `ceramic` and `powder` stay as they are. `herco_private.coating_price_rules` and the
-- legacy dispatch are NOT touched here (retired in a later migration).
-- Saved bookings are never rewritten: this migration only changes how NEW or EDITED work is priced.
--
-- OWNER-AUTHORIZED RELEASE STEP (not done in SQL): storage buckets are created outside migrations
-- (see 202611190030, which only guards `herco-completion`). Before the swatch upload endpoint works on an
-- environment, create the PUBLIC bucket `herco-swatches` (public = true, file size limit 4194304,
-- allowed types image/jpeg, image/png, image/webp). `herco_pricing_swatch_target` refuses (55000) until it exists.
begin;

-- Normalised size key and price for one wheel line. Returns null when the shop must quote.
-- Order: enabled exception -> colour per-size price -> category base price -> quote.
create function herco_private.powder_wheel_rate(config jsonb, bike text, c jsonb)
returns jsonb language plpgsql stable set search_path='' as $$
declare m jsonb:=config->'powderModel'; wt text:=coalesce(c->>'wheel_type',''); bk text:=lower(btrim(coalesce(bike,'')));
 finish text:=lower(btrim(coalesce(c->>'finish',''))); sz text; cat text; entry jsonb; ex jsonb; rate jsonb;
begin
 if finish='' then return null; end if; -- no colour chosen yet: the shop quotes
 sz:=m->'bikeTiers'->>bk;
 if sz is null then
  sz:=case wt when '10–14 inches' then '10-14' when '17 inches (Raider / Sniper only)' then '17' when 'Big bike / sports bike' then 'big-bike'
   when '10-14' then '10-14' when '17' then '17' when 'big-bike' then 'big-bike' else 'not-sure' end;
 end if;
 select e.value into entry from jsonb_array_elements(coalesce(m->'colorEntries','[]')) e where lower(e.value->>'id')=finish or lower(btrim(e.value->>'name'))=finish limit 1; -- enabled only hides a colour from customers; it never changes its price
 cat:=entry->>'category'; -- null when no colour matches: the shop quotes (after any exception below)
 -- 1. Exception first. A from-finish only matches when the booking states one (key `from_finish`).
 select x.value into ex from jsonb_array_elements(coalesce(m->'exceptions','[]')) x
 where coalesce((x.value->>'enabled')::boolean,false) and coalesce(x.value->>'service','wheel-colour')='wheel-colour' and x.value->>'bikeKey'=bk
  and lower(btrim(x.value->>'finish'))=any(array[finish,lower(coalesce(entry->>'id','')),lower(btrim(coalesce(entry->>'name','')))])
  and (x.value->>'fromFinish' is null or lower(btrim(x.value->>'fromFinish'))=lower(btrim(coalesce(c->>'from_finish',''))))
 order by (x.value->>'fromFinish' is not null) desc limit 1;
 if found then
  if ex->>'quoteOnly'='true' or ex->>'priceCentavos' is null then return null; end if;
  return to_jsonb(round((ex->>'priceCentavos')::numeric/100,2));
 end if;
 -- 2. Base. Quote-only colours, Custom, and "Not sure" always quote.
 if entry is null or cat='custom' or sz='not-sure' or entry->>'quoteOnly'='true' then return null; end if;
 if c->'prismatic'='true' then cat:='luminous-prismatic'; end if;
 rate:=coalesce(nullif(entry->'pricesBySize'->sz,'null'::jsonb),m->'baseTable'->cat->sz);
 return nullif(rate,'null'::jsonb);
end $$;
revoke all on function herco_private.powder_wheel_rate(jsonb,text,jsonb) from public,anon,authenticated;

-- Shape check for config->'powderModel'. Any malformed value (or cast failure) means false.
create function herco_private.valid_powder_model(model jsonb)
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
   or not coalesce(ex ?& array['id','bikeKey','finish','enabled'],false) then return false; end if;
  if jsonb_typeof(ex->'id')<>'string' or ex->>'id' !~ uuid_pattern or (ex->>'id')=any(ids) then return false; end if;
  ids:=ids||(ex->>'id');
  if ex ? 'service' and ex->'service' is distinct from '"wheel-colour"'::jsonb then return false; end if;
  if jsonb_typeof(ex->'bikeKey')<>'string' or char_length(ex->>'bikeKey') not between 1 and 120 or ex->>'bikeKey'<>lower(btrim(ex->>'bikeKey')) then return false; end if;
  if jsonb_typeof(ex->'finish')<>'string' or char_length(btrim(ex->>'finish')) not between 1 and 100 then return false; end if;
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
  sig:=coalesce(ex->>'service','wheel-colour')||'|'||(ex->>'bikeKey')||'|'||lower(btrim(ex->>'finish'))||'|'||lower(btrim(coalesce(ex->>'fromFinish','')));
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

-- Seed once: confirmed base prices (pesos), 7 Basic colours, the other known colours as Special.
update herco_private.ui_pricing set revision=revision+1,config=config||jsonb_build_object('powderModel',jsonb_build_object(
 'categories','["basic","special","luminous-prismatic","custom"]'::jsonb,
 'baseTable','{"basic":{"10-14":2199,"17":3199,"big-bike":4499,"not-sure":null},"special":{"10-14":2499,"17":3499,"big-bike":5499,"not-sure":null},"luminous-prismatic":{"10-14":2999,"17":3999,"big-bike":6999,"not-sure":null},"custom":{"10-14":null,"17":null,"big-bike":null,"not-sure":null}}'::jsonb,
 'colorEntries',(select jsonb_agg(jsonb_build_object('id',gen_random_uuid()::text,'name',v.name,'category',v.category,'photoPath',null::text,'quoteOnly',false,'enabled',true) order by v.ord)
  from(values(1,'Black','basic'),(2,'White','basic'),(3,'Glossy Black','basic'),(4,'Snow White','basic'),(5,'Matte Black','basic'),(6,'Crystal Black','basic'),(7,'Pristine White','basic'),
   (8,'Graphite Black','special'),(9,'Dry Bronze','special'),(10,'Pearl White','special'),(11,'High Gloss Black','special'),(12,'High Gloss White','special'),(13,'Fire Blue','special'))v(ord,name,category)),
 'exceptions','[]'::jsonb,'bikeTiers','{}'::jsonb))
where singleton and not (config ? 'powderModel');
do $$ begin
 if exists(select 1 from herco_private.ui_pricing where singleton and config ? 'powderModel' and not herco_private.valid_powder_model(config->'powderModel')) then
  raise exception 'Seeded powder model is invalid.'; end if;
end $$;

-- Same checks, order, lock, replay and audit as before, plus the powder model.
-- A save that omits powderModel (an older screen) keeps the stored model, so nothing breaks during rollout.
create or replace function public.herco_save_ui_pricing(request_id uuid,expected_revision integer,configuration jsonb)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare grants text[]:=herco_private.pricing_grants(); previous herco_private.ui_pricing; prior herco_private.ui_pricing_audit; saved jsonb; incoming_model boolean;
begin
 if not ('changePricing'=any(grants)) then raise exception 'Pricing permission required.' using errcode='42501'; end if;
 if request_id is null or expected_revision is null or configuration is null or jsonb_typeof(configuration)<>'object' or pg_column_size(configuration)>40000 or not configuration ?& array['ceramic','powder'] or not (configuration->'ceramic') ?& array['tiers','addons','listedAddons','premiumGloss'] or not (configuration->'powder') ?& array['parts','wheelRates','prismatic','extras','largeSwingarm'] or not herco_private.valid_price_tree(configuration-'powderModel') or not (configuration->'ceramic'->'tiers') ?& array['1799','1999','2499'] or not (configuration->'ceramic'->'addons') ?& array['Matte to Glossy','Inner coating','Graphene coating','Mags coating','Helmet coating','K3 bracket / crashguard removal','Decals removal'] or not (configuration->'ceramic'->'listedAddons') ?& array['Matte to Glossy','Inner coating','Graphene coating']
  or (configuration ? 'powderModel' and not herco_private.valid_powder_model(configuration->'powderModel')) then raise exception 'Check the coating rates.' using errcode='22023'; end if;
 incoming_model:=configuration ? 'powderModel';
 perform pg_advisory_xact_lock(72017,hashtext(auth.uid()::text||request_id::text));
 select * into prior from herco_private.ui_pricing_audit a where a.actor_id=auth.uid() and a.request_id=herco_save_ui_pricing.request_id;
 if found then
  if (prior.after_value->'config')-'powderModel'<>configuration-'powderModel' or (incoming_model and prior.after_value->'config'->'powderModel'<>configuration->'powderModel') then raise exception 'Request ID already used.' using errcode='22023'; end if;
  return prior.after_value;
 end if;
 select * into strict previous from herco_private.ui_pricing where singleton for update;
 if previous.revision<>expected_revision then raise exception 'Prices changed. Reload before editing.' using errcode='40001'; end if;
 if not incoming_model and previous.config ? 'powderModel' then configuration:=configuration||jsonb_build_object('powderModel',previous.config->'powderModel'); end if;
 update herco_private.ui_pricing set config=configuration,revision=revision+1 where singleton returning jsonb_build_object('config',config,'revision',revision) into saved;
 insert into herco_private.ui_pricing_audit values(auth.uid(),request_id,to_jsonb(previous),saved,now()); return saved;
end $$;
revoke all on function public.herco_save_ui_pricing(uuid,integer,jsonb) from public,anon,authenticated;
grant execute on function public.herco_save_ui_pricing(uuid,integer,jsonb) to authenticated;

-- Same output shape and promotion handling as before; only the wheel price now comes from the powder model
-- (exception -> base -> quote) when config->'powderModel' exists. Legacy fallback (no ui_catalog) is untouched.
create or replace function herco_private.coating_price_lines(base_lines jsonb,bike text,options jsonb)
returns jsonb language plpgsql stable set search_path='' as $$
declare config jsonb; c jsonb:=options->'ui_catalog'; line jsonb; detail jsonb; details jsonb; result jsonb:='[]'; promo herco_private.booking_promotion; tier text; part text; rate jsonb; amount bigint; maximum bigint; quoted boolean;
begin
 if c is null then return herco_private.coating_price_lines_legacy(base_lines,bike,options); end if;
 select p.config into config from herco_private.ui_pricing p where singleton;
 select p.* into promo from herco_private.booking_promotion p where p.singleton and p.enabled;
 tier:=case when c->'other_big_bike'='true' then '2499' else config->'ceramic'->'models'->>bike end;
 if tier is null and c->'big_bike'='true' then tier:='2499'; end if;
 for line in select value from jsonb_array_elements(base_lines) loop
  details:='[]';
  if line->>'code'='ceramic' then
   details:=jsonb_build_array(herco_private.ui_component_price('ceramic','Ceramic coating',config->'ceramic'->'tiers'->tier,promo));
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

-- Customers read the config to price their booking. Staff-only exception notes, disabled exceptions and disabled colours stay private.
create or replace function public.herco_booking_ui_catalog()
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not exists(select 1 from auth.users where id=auth.uid() and email_confirmed_at is not null) then
  raise exception 'Sign in with a verified account.' using errcode='42501'; end if;
 return(select jsonb_build_object('config',case when jsonb_typeof(p.config->'powderModel')='object'
  then jsonb_set(jsonb_set(p.config,'{powderModel,exceptions}',coalesce((select jsonb_agg(e.value-'note') from jsonb_array_elements(coalesce(p.config->'powderModel'->'exceptions','[]')) e where e.value->'enabled'='true'::jsonb),'[]'::jsonb)),
   '{powderModel,colorEntries}',coalesce((select jsonb_agg(c.value order by c.ord) from jsonb_array_elements(coalesce(p.config->'powderModel'->'colorEntries','[]')) with ordinality c(value,ord) where coalesce(c.value->'enabled','true'::jsonb)<>'false'::jsonb),'[]'::jsonb))
  else p.config end,'revision',p.revision) from herco_private.ui_pricing p where singleton);
end $$;
revoke all on function public.herco_booking_ui_catalog() from public,anon,authenticated;
grant execute on function public.herco_booking_ui_catalog() to authenticated;

-- Public swatch bucket (separate from private completion evidence). Browser clients may read it but never write it.
create policy herco_swatches_insert_server_only on storage.objects as restrictive for insert to anon,authenticated with check (bucket_id <> 'herco-swatches');
create policy herco_swatches_update_server_only on storage.objects as restrictive for update to anon,authenticated using (bucket_id <> 'herco-swatches') with check (bucket_id <> 'herco-swatches');
create policy herco_swatches_delete_server_only on storage.objects as restrictive for delete to anon,authenticated using (bucket_id <> 'herco-swatches');

create function herco_private.require_public_swatch_bucket()
returns void language plpgsql stable set search_path='' as $$
declare allowed_types text[]:=array['image/jpeg','image/png','image/webp'];
begin
 if not exists(select 1 from storage.buckets b where b.id='herco-swatches' and b.public is true and b.file_size_limit between 1 and 4194304
  and b.allowed_mime_types @> allowed_types and b.allowed_mime_types <@ allowed_types) then
  raise exception 'Swatch photo storage is unavailable.' using errcode='55000'; end if;
end $$;
revoke all on function herco_private.require_public_swatch_bucket() from public,anon,authenticated;

-- Returns the storage path stem 'entry/<id>' (the server appends the extension). The colour entry must already be saved.
create function public.herco_pricing_swatch_target(entry uuid)
returns text language plpgsql stable security definer set search_path='' as $$
declare grants text[]:=herco_private.pricing_grants();
begin
 if not ('changePricing'=any(grants)) then raise exception 'Pricing permission required.' using errcode='42501'; end if;
 if entry is null or not exists(select 1 from herco_private.ui_pricing p,jsonb_array_elements(coalesce(p.config->'powderModel'->'colorEntries','[]')) e where p.singleton and e.value->>'id'=entry::text) then
  raise exception 'Choose a saved colour entry.' using errcode='22023'; end if;
 perform herco_private.require_public_swatch_bucket();
 return 'entry/'||entry::text;
end $$;
revoke all on function public.herco_pricing_swatch_target(uuid) from public,anon,authenticated;
grant execute on function public.herco_pricing_swatch_target(uuid) to authenticated;

notify pgrst,'reload schema';
commit;
