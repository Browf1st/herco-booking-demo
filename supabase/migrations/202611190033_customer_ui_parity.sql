begin;

-- UI catalog values are configured separately; migrations never enable sample prices.
create table herco_private.ui_pricing (
 singleton boolean primary key default true check(singleton),
 config jsonb not null default '{}' check(jsonb_typeof(config)='object'),
 revision integer not null default 1 check(revision>0)
);
alter table herco_private.ui_pricing enable row level security;
revoke all on herco_private.ui_pricing from public,anon,authenticated;
insert into herco_private.ui_pricing(singleton) values(true);
alter table public.herco_bookings add column reference_no bigint generated always as identity;
create unique index herco_bookings_reference_no on public.herco_bookings(reference_no);

create function public.herco_booking_ui_catalog()
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not exists(select 1 from auth.users where id=auth.uid() and email_confirmed_at is not null) then
  raise exception 'Sign in with a verified account.' using errcode='42501'; end if;
 return(select jsonb_build_object('config',p.config,'revision',p.revision) from herco_private.ui_pricing p where singleton);
end $$;
revoke all on function public.herco_booking_ui_catalog() from public,anon,authenticated;
grant execute on function public.herco_booking_ui_catalog() to authenticated;

alter function herco_private.normalize_coating_options(jsonb,text[],text) rename to normalize_coating_options_legacy;
create function herco_private.normalize_coating_options(options jsonb,service_codes text[],bike text)
returns jsonb language plpgsql immutable set search_path='' as $$
declare normalized jsonb; c jsonb; k text; value text; result jsonb;
begin
 normalized:=herco_private.normalize_coating_options_legacy(options-'ui_catalog',service_codes,bike);
 if not options?'ui_catalog' then return normalized; end if;
 c:=options->'ui_catalog';
 if jsonb_typeof(c)<>'object' or octet_length(c::text)>2500 or exists(select 1 from jsonb_object_keys(c) x where x not in
 ('ceramic_addons','wheel_type','prismatic','wheel_extras','big_bike','other_big_bike','finish','model_year','notes')) then
  raise exception 'Check your service options.' using errcode='22023'; end if;
 foreach k in array array['ceramic_addons','wheel_extras'] loop
  if c?k and (jsonb_typeof(c->k)<>'array' or jsonb_array_length(c->k)>12) then raise exception 'Check your selected add-ons.' using errcode='22023'; end if;
  for value in select jsonb_array_elements_text(coalesce(c->k,'[]')) loop
   if (k='ceramic_addons' and value not in('Matte to Glossy','Inner coating','Graphene coating','Mags coating','Helmet coating','K3 bracket / crashguard removal','Decals removal'))
    or (k='wheel_extras' and value not in('Aftermarket mags','Previously powder-coated mags','Protective top coat')) then
    raise exception 'Choose valid add-ons.' using errcode='22023'; end if;
  end loop;
 end loop;
 foreach k in array array['prismatic','big_bike','other_big_bike'] loop
  if c?k and jsonb_typeof(c->k)<>'boolean' then raise exception 'Check your motorcycle options.' using errcode='22023'; end if;
 end loop;
 if char_length(coalesce(c->>'notes',''))>700 or char_length(coalesce(c->>'finish',''))>100
  or (c?'model_year' and (jsonb_typeof(c->'model_year')<>'number' or (c->>'model_year')!~'^\d{4}$' or (c->>'model_year')::integer not between 1980 and 2100))
  or coalesce(c->>'wheel_type','') not in('','10–14 inches','17 inches (Raider / Sniper only)','Big bike / sports bike','Not sure') then
  raise exception 'Check the motorcycle year, notes and wheel configuration.' using errcode='22023'; end if;
 if not('ceramic'=any(service_codes)) and jsonb_array_length(coalesce(c->'ceramic_addons','[]'))>0 then raise exception 'Ceramic add-ons require ceramic coating.' using errcode='22023'; end if;
 if not('wheel-colour'=any(service_codes)) and (coalesce(c->>'finish','')<>'' or coalesce(c->>'wheel_type','')<>'' or jsonb_array_length(coalesce(c->'wheel_extras','[]'))>0 or c->'prismatic'='true') then raise exception 'Powder options require powder coating.' using errcode='22023'; end if;
 if coalesce(c->>'wheel_type','')<>'' and not(coalesce(normalized->'powder_parts','[]')?'Wheels / mags') then raise exception 'Choose mags before a wheel category.' using errcode='22023'; end if;
 result:=jsonb_build_object('ceramic_addons',(select coalesce(jsonb_agg(v order by v),'[]') from(select distinct jsonb_array_elements_text(coalesce(c->'ceramic_addons','[]')) v)s),
 'wheel_type',coalesce(c->>'wheel_type',''),'prismatic',coalesce(c->'prismatic','false'),'wheel_extras',(select coalesce(jsonb_agg(v order by v),'[]') from(select distinct jsonb_array_elements_text(coalesce(c->'wheel_extras','[]')) v)s),
 'big_bike',coalesce(c->'big_bike','false'),'other_big_bike',coalesce(c->'other_big_bike','false'),'finish',btrim(coalesce(c->>'finish','')),'notes',btrim(coalesce(c->>'notes','')));
 if c?'model_year' then result:=result||jsonb_build_object('model_year',(c->>'model_year')::integer); end if;
 return normalized||jsonb_build_object('ui_catalog',result);
end $$;
revoke all on function herco_private.normalize_coating_options(jsonb,text[],text) from public,anon,authenticated;

create function herco_private.ui_component_price(code text,label text,rate jsonb,promo herco_private.booking_promotion)
returns jsonb language plpgsql immutable set search_path='' as $$
declare low bigint; high bigint; discount integer;
begin
 if rate is null or jsonb_typeof(rate) not in('array','number') then return jsonb_build_object('code',code,'label',label,'price_centavos',0,'quote_required',true); end if;
 low:=round((case when jsonb_typeof(rate)='number' then rate#>>'{}' else rate->>0 end)::numeric*100);
 high:=round((case when jsonb_typeof(rate)='number' then rate#>>'{}' else rate->>1 end)::numeric*100);
 if low is null or high is null or low<0 or high<low or high>2147483647 then raise exception 'The shop must correct its catalog pricing.' using errcode='22023'; end if;
 discount:=herco_private.pricing_discount(low::integer,coalesce(promo.discount_basis_points,0));
 return jsonb_strip_nulls(jsonb_build_object('code',code,'label',label,'price_centavos',low-discount,'max_centavos',case when high>low then high-herco_private.pricing_discount(high::integer,coalesce(promo.discount_basis_points,0)) end,'promotion',herco_private.promotion_snapshot(promo,low::integer,discount)));
end $$;
revoke all on function herco_private.ui_component_price(text,text,jsonb,herco_private.booking_promotion) from public,anon,authenticated;

alter function herco_private.coating_price_lines(jsonb,text,jsonb) rename to coating_price_lines_legacy;
create function herco_private.coating_price_lines(base_lines jsonb,bike text,options jsonb)
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
     rate:=case when c->'prismatic'='true' then config->'powder'->'prismatic'->(c->>'wheel_type') else config->'powder'->'wheelRates'->(c->>'wheel_type') end;
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

-- Calendar navigation and mutations share the same bounded booking horizon.
create or replace function public.herco_availability(from_date date, to_date date)
returns table (visit_date date, visit_hour smallint, status text)
language plpgsql stable security definer set search_path = '' as $$
declare
  shop_now timestamp := statement_timestamp() at time zone 'Asia/Manila';
begin
  if from_date is null or to_date is null or from_date < shop_now::date - 31
    or to_date < from_date or to_date-from_date > 41 or to_date > shop_now::date + 365 then
    raise exception 'Choose up to 42 dates within the booking calendar.' using errcode = '22023';
  end if;

  return query
    select from_date + day_offset, hour::smallint,
      herco_private.slot_status(from_date + day_offset, hour::smallint, shop_now)
    from generate_series(0, to_date - from_date) as day_offset
    cross join generate_series(9, 16) as hour
    order by day_offset, hour;
end
$$;

create or replace function public.herco_request_booking_change(
  booking_id uuid, submission_id uuid, kind text, reason text default '',
  target_date date default null, target_hour smallint default null
)
returns uuid
language plpgsql volatile security definer set search_path = '' as $$
declare
  actor uuid := auth.uid();
  shop_now timestamp;
  booking public.herco_bookings;
  request herco_private.booking_change_requests;
  note text := btrim(coalesce(reason, ''));
begin
  if actor is null then raise exception 'Sign in to request a change.' using errcode = '42501'; end if;
  if booking_id is null or submission_id is null or kind is null or kind not in ('cancel', 'reschedule')
    or char_length(note) > 500
    or (kind = 'cancel' and (target_date is not null or target_hour is not null))
    or (kind = 'reschedule' and (target_date is null or not isfinite(target_date) or target_hour is null or target_hour not between 9 and 16)) then
    raise exception 'Check the booking, requested visit and reason.' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(72003, hashtext(actor::text || ':' || submission_id::text));
  select r.* into request from herco_private.booking_change_requests r
    where r.customer_id = actor and r.submission_id = herco_request_booking_change.submission_id;
  if found then
    if request.booking_id is distinct from booking_id or request.kind is distinct from kind
      or request.reason is distinct from note or request.target_date is distinct from target_date
      or request.target_hour is distinct from target_hour then
      raise exception 'This request ID belongs to a different change.' using errcode = '22023';
    end if;
    return request.id;
  end if;

  select b.* into booking from public.herco_bookings b
    where b.id = herco_request_booking_change.booking_id and b.customer_id = actor for update;
  if not found then raise exception 'This booking could not be found.' using errcode = 'P0002'; end if;
  if booking.booking_kind = 'walk_in' then
    raise exception 'Ask the shop to change or cancel your walk-in.' using errcode = '23P01';
  end if;
  shop_now := clock_timestamp() at time zone 'Asia/Manila';
  if booking.status not in ('pending', 'confirmed')
    or booking.visit_date + make_time(booking.visit_hour, 0, 0) <= shop_now then
    raise exception 'Only active future bookings can be changed.' using errcode = '23P01';
  end if;
  if exists (select 1 from herco_private.booking_change_requests r where r.booking_id = booking.id and r.state = 'pending') then
    raise exception 'This booking already has a pending request.' using errcode = '23P01';
  end if;
  if kind = 'reschedule' and (target_date < shop_now::date or target_date > shop_now::date + 365
    or herco_private.slot_status(target_date, target_hour, shop_now) <> 'open') then
    raise exception 'Pick another appointment time.' using errcode = '23P01';
  end if;

  insert into herco_private.booking_change_requests (
    booking_id, customer_id, submission_id, kind, reason, original_date, original_hour, target_date, target_hour
  ) values (booking.id, actor, submission_id, kind, note, booking.visit_date, booking.visit_hour, target_date, target_hour)
  returning * into request;
  insert into public.herco_booking_events (booking_id, actor_id, kind, to_status)
  values (booking.id, actor, 'booking_' || kind || '_requested', booking.status);
  return request.id;
end
$$;

create or replace function public.herco_review_booking_change(request_id uuid, decision text)
returns void
language plpgsql volatile security definer set search_path = '' as $$
declare
  grants text[] := herco_private.staff_change_grants();
  request herco_private.booking_change_requests;
  booking public.herco_bookings;
  shop_now timestamp;
  event_kind text;
  event_id bigint;
begin
  if request_id is null or decision is null or decision not in ('approved', 'declined') then
    raise exception 'Choose a valid request and decision.' using errcode = '22023';
  end if;
  select r.* into request from herco_private.booking_change_requests r where r.id = request_id;
  if not found then raise exception 'This change request could not be found.' using errcode = 'P0002'; end if;
  if (case when request.kind = 'cancel' then 'reviewCancellation' = any(grants)
      else 'reviewReschedule' = any(grants) end) is not true then
    raise exception 'You do not have permission to review this request.' using errcode = '42501';
  end if;

  -- Booking mutations take the booking row before the request row and day locks.
  select b.* into strict booking from public.herco_bookings b where b.id = request.booking_id for update;
  select r.* into strict request from herco_private.booking_change_requests r where r.id = request_id for update;
  if request.state = decision then return; end if;
  if request.state <> 'pending' then
    raise exception 'This request has already been reviewed.' using errcode = '23P01';
  end if;

  if decision = 'approved' then
    if booking.status not in ('pending', 'confirmed') or
      (booking.visit_date, booking.visit_hour) is distinct from (request.original_date, request.original_hour) then
      raise exception 'The original booking changed. Decline this request and ask for a new one.' using errcode = '23P01';
    end if;
    if request.kind = 'reschedule' then
      perform pg_advisory_xact_lock(72002, least(booking.visit_date, request.target_date) - date '2000-01-01');
      if booking.visit_date <> request.target_date then
        perform pg_advisory_xact_lock(72002, greatest(booking.visit_date, request.target_date) - date '2000-01-01');
      end if;
    else
      perform pg_advisory_xact_lock(72002, booking.visit_date - date '2000-01-01');
    end if;

    shop_now := clock_timestamp() at time zone 'Asia/Manila';
    if booking.visit_date + make_time(booking.visit_hour, 0, 0) <= shop_now then
      raise exception 'The original visit has started. This request can only be declined.' using errcode = '23P01';
    end if;
    if request.kind = 'cancel' then
      update public.herco_bookings set status = 'cancelled' where id = booking.id returning * into booking;
    else
      if request.target_date > shop_now::date + 365
        or herco_private.slot_status(request.target_date, request.target_hour, shop_now) <> 'open'
        or exists (
          select 1 from jsonb_array_elements(coalesce(booking.current_services, booking.original_services)) as service
          left join herco_private.services s on s.code = service->>'code'
          where (extract(dow from request.target_date)::smallint = any(s.appointment_days)) is not true
        ) then
        raise exception 'The requested time is no longer available for this visit.' using errcode = '23P01';
      end if;
      update public.herco_bookings set visit_date = request.target_date, visit_hour = request.target_hour
        where id = booking.id returning * into booking;
    end if;
  end if;

  update herco_private.booking_change_requests set state = decision,
    reviewed_by = auth.uid(), reviewed_at = clock_timestamp() where id = request_id;
  event_kind := 'booking_' || request.kind || '_' || decision;
  insert into public.herco_booking_events (booking_id, actor_id, kind, to_status)
  values (booking.id, auth.uid(), event_kind, booking.status) returning id into event_id;
  insert into herco_private.notification_outbox (event_id, template, recipient, payload)
  values (event_id, event_kind, booking.customer_contact->>'email', jsonb_build_object(
    'booking_id', booking.id, 'visit_date', booking.visit_date, 'visit_hour', booking.visit_hour));
end
$$;

create or replace function herco_private.create_booking_for(
  actor uuid,
  customer uuid,
  booked_by_staff boolean,
  request_id uuid,
  visit_date date,
  visit_hour smallint,
  service_codes text[],
  bike text,
  customer_name text,
  customer_phone text,
  plate_number text default ''
)
returns public.herco_bookings
language plpgsql volatile set search_path = '' as $$
declare
  customer_email text;
  shop_now timestamp;
  selected_codes text[];
  requested jsonb;
  contact jsonb;
  services jsonb;
  service_count integer;
  total bigint;
  eligible boolean;
  booking public.herco_bookings;
  booking_event_id bigint;
begin
  if actor is null or customer is null then
    raise exception 'Sign in before booking.' using errcode = '42501';
  end if;

  select u.email into customer_email from auth.users as u
    where u.id = customer and u.email_confirmed_at is not null;
  if customer_email is null then
    raise exception 'Verify your email before booking.' using errcode = '42501';
  end if;

  if request_id is null or visit_date is null or not isfinite(visit_date) or visit_hour is null or visit_hour not between 9 and 16
    or coalesce(cardinality(service_codes), 0) not between 1 and 20
    or coalesce(char_length(btrim(bike)), 0) not between 1 and 120
    or coalesce(char_length(btrim(customer_name)), 0) not between 1 and 120
    or coalesce(char_length(btrim(customer_phone)), 0) not between 3 and 40
    or coalesce(char_length(btrim(plate_number)), 0) > 30 then
    raise exception 'Check the visit, selected services and contact details.' using errcode = '22023';
  end if;

  select array_agg(distinct code order by code) into selected_codes from unnest(service_codes) as code;
  if cardinality(selected_codes) <> cardinality(service_codes) or array_position(selected_codes, null) is not null then
    raise exception 'Choose each service once.' using errcode = '22023';
  end if;
  contact := jsonb_build_object('name', btrim(customer_name), 'phone', btrim(customer_phone),
    'email', customer_email, 'plate', coalesce(btrim(plate_number), ''));
  requested := jsonb_build_object('date', visit_date, 'hour', visit_hour, 'bike', btrim(bike),
    'services', to_jsonb(selected_codes), 'name', contact->'name', 'phone', contact->'phone', 'plate', contact->'plate');

  if booked_by_staff then
    requested := requested || jsonb_build_object('staff_actor_id', actor);
  end if;

  -- Serialize identical request IDs before competing for a date.
  perform pg_advisory_xact_lock(72001, hashtext(customer::text || ':' || request_id::text));
  select b.* into booking from public.herco_bookings as b
    where b.customer_id = customer and b.request_id = create_booking_for.request_id;
  if found then
    if booking.request_payload <> requested then
      raise exception 'This request ID belongs to a different booking.' using errcode = '22023';
    end if;
    return booking;
  end if;

  -- Scheduling writes must take this same day lock before changing availability.
  perform pg_advisory_xact_lock(72002, visit_date - date '2000-01-01');
  shop_now := clock_timestamp() at time zone 'Asia/Manila';
  if visit_date < shop_now::date or visit_date > shop_now::date + 365
    or herco_private.slot_status(visit_date, visit_hour, shop_now) <> 'open' then
    raise exception 'That appointment time is unavailable. Choose another slot.' using errcode = '23P01';
  end if;

  select count(*), sum(s.price_centavos),
    bool_and(extract(dow from visit_date)::smallint = any (s.appointment_days)),
    jsonb_agg(jsonb_build_object('code', s.code, 'label', s.label, 'price_centavos', s.price_centavos) order by s.code)
  into service_count, total, eligible, services
  from herco_private.services as s where s.enabled and s.code = any (selected_codes);
  if service_count <> cardinality(selected_codes) or eligible is not true then
    raise exception 'One or more services are unavailable on that date.' using errcode = '22023';
  end if;

  insert into public.herco_bookings (customer_id, request_id, request_payload, visit_date,
    visit_hour, bike, customer_contact, original_services, original_total_centavos)
  values (customer, request_id, requested, visit_date, visit_hour, btrim(bike), contact, services, total)
  returning * into booking;

  insert into public.herco_booking_events (booking_id, actor_id, kind, to_status)
  values (booking.id, actor, case when booked_by_staff then 'booking_created_by_staff' else 'booking_submitted' end, 'pending')
  returning id into booking_event_id;

  insert into herco_private.notification_outbox (event_id, template, recipient, payload)
  values (booking_event_id, 'booking_submitted', customer_email, jsonb_build_object(
    'booking_id', booking.id, 'visit_date', visit_date, 'visit_hour', visit_hour));
  return booking;
end
$$;

create or replace function public.herco_staff_change_booking(
  booking_id uuid, request_id uuid, kind text, original_date date, original_hour smallint,
  reason text default '', target_date date default null, target_hour smallint default null
)
returns void
language plpgsql volatile security definer set search_path = '' as $$
declare
  grants text[] := herco_private.staff_booking_grants();
  actor uuid := auth.uid();
  note text := btrim(coalesce(reason, ''));
  change_data jsonb;
  replay jsonb;
  booking public.herco_bookings;
  shop_now timestamp;
  event_kind text;
  event_id bigint;
begin
  if booking_id is null or request_id is null or kind is null or kind not in ('cancel', 'reschedule')
    or original_date is null or not isfinite(original_date) or (original_hour is not null and original_hour not between 9 and 16)
    or char_length(note) > 500
    or (kind = 'cancel' and (target_date is not null or target_hour is not null))
    or (kind = 'reschedule' and (original_hour is null or target_date is null or not isfinite(target_date) or target_hour is null or target_hour not between 9 and 16
      or (target_date, target_hour) = (original_date, original_hour))) then
    raise exception 'Check the booking, reason and new visit.' using errcode = '22023';
  end if;
  if (case when kind = 'cancel' then 'cancelBooking' = any(grants)
    else 'rescheduleBooking' = any(grants) end) is not true then
    raise exception 'You do not have permission for this booking change.' using errcode = '42501';
  end if;

  change_data := jsonb_build_object('bookingId', booking_id, 'kind', kind, 'reason', note,
    'originalDate', original_date, 'originalHour', original_hour, 'targetDate', target_date, 'targetHour', target_hour);
  perform pg_advisory_xact_lock(72004, hashtext(actor::text || ':' || request_id::text));
  select c.details into replay from herco_private.staff_booking_changes c
    where c.actor_id = actor and c.request_id = herco_staff_change_booking.request_id;
  if found then
    if replay is distinct from change_data then
      raise exception 'This request ID belongs to another booking change.' using errcode = '22023';
    end if;
    return;
  end if;

  select b.* into booking from public.herco_bookings b where b.id = booking_id for update;
  if not found then raise exception 'Booking not found.' using errcode = 'P0002'; end if;
  if booking.status not in ('pending', 'confirmed') or
    (booking.visit_date, booking.visit_hour) is distinct from (original_date, original_hour) then
    raise exception 'This booking has changed. Reload the schedule before trying again.' using errcode = '23P01';
  end if;
  if exists (select 1 from herco_private.booking_change_requests r where r.booking_id = booking.id and r.state = 'pending') then
    raise exception 'Review the customer’s pending change request before changing the booking directly.' using errcode = '23P01';
  end if;

  perform pg_advisory_xact_lock(72002, least(original_date, coalesce(target_date, original_date)) - date '2000-01-01');
  if target_date is not null and original_date <> target_date then
    perform pg_advisory_xact_lock(72002, greatest(original_date, target_date) - date '2000-01-01');
  end if;
  shop_now := clock_timestamp() at time zone 'Asia/Manila';
  if (booking.booking_kind = 'walk_in' and original_date <> shop_now::date)
    or (booking.booking_kind = 'appointment' and original_date + make_time(original_hour, 0, 0) <= shop_now) then
    raise exception 'The original visit has already started.' using errcode = '23P01';
  end if;

  if kind = 'cancel' then
    update public.herco_bookings set status = 'cancelled' where id = booking.id returning * into booking;
    event_kind := 'booking_cancelled_by_staff';
  else
    if target_date > shop_now::date + 365 or herco_private.slot_status(target_date, target_hour, shop_now) <> 'open'
      or exists (
        select 1 from jsonb_array_elements(coalesce(booking.current_services, booking.original_services)) service
        left join herco_private.services s on s.code = service->>'code'
        where (extract(dow from target_date)::smallint = any(s.appointment_days)) is not true
      ) then
      raise exception 'The requested time is unavailable for this booking’s current services.' using errcode = '23P01';
    end if;
    update public.herco_bookings set visit_date = target_date, visit_hour = target_hour
      where id = booking.id returning * into booking;
    event_kind := 'booking_rescheduled_by_staff';
  end if;
  insert into public.herco_booking_events (booking_id, actor_id, kind, to_status)
    values (booking.id, actor, event_kind, booking.status) returning id into event_id;
  insert into herco_private.staff_booking_changes values (actor, request_id, booking.id, event_id, change_data);
  insert into herco_private.notification_outbox (event_id, template, recipient, payload)
    values (event_id, case when booking.booking_kind = 'walk_in' then 'walk_in_cancelled' else event_kind end,
      booking.customer_contact->>'email', jsonb_build_object(
      'booking_id', booking.id, 'visit_date', booking.visit_date, 'visit_hour', booking.visit_hour));
end
$$;


-- Original coating configuration remains immutable; later changes have their own snapshot.
alter table public.herco_bookings add column current_coating_options jsonb check(current_coating_options is null or jsonb_typeof(current_coating_options)='object');
alter table herco_private.booking_service_changes add column before_options jsonb,add column after_options jsonb;
alter function public.herco_booked_services(uuid) rename to herco_booked_services_legacy;
create function public.herco_booked_services(booking_id uuid)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare result jsonb;booking public.herco_bookings;
begin
 result:=public.herco_booked_services_legacy(booking_id);
 select b.* into strict booking from public.herco_bookings b where b.id=booking_id;
 return result||jsonb_build_object('bike',booking.bike,'options',coalesce(booking.current_coating_options,booking.coating_options));
end $$;
revoke all on function public.herco_booked_services(uuid) from public,anon,authenticated;
grant execute on function public.herco_booked_services(uuid) to authenticated;

create function public.herco_save_booked_services_configured(booking_id uuid,request_id uuid,expected_revision integer,service_codes text[],options jsonb,expected_price_fingerprint text default null)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare booking public.herco_bookings;previous herco_private.booking_service_changes;normalized jsonb;selected text[];old_lines jsonb;new_lines jsonb;old_options jsonb;editable boolean;
begin
 if request_id is null or expected_revision is null or expected_revision<0 or coalesce(cardinality(service_codes),0) not between 1 and 20 or array_position(service_codes,null) is not null then raise exception 'Choose valid services.' using errcode='22023';end if;
 select b.* into booking from public.herco_bookings b where b.id=booking_id for update;
 if not found then raise exception 'Booking not found.' using errcode='P0002';end if;
 editable:=herco_private.may_edit_booked_services(booking);
 normalized:=herco_private.normalize_coating_options(options,service_codes,booking.bike);
 select array_agg(distinct code order by code) into selected from unnest(service_codes)code;
 if cardinality(selected)<>cardinality(service_codes) then raise exception 'Choose each service once.' using errcode='22023';end if;
 select c.* into previous from herco_private.booking_service_changes c where c.booking_id=booking.id and c.actor_id=auth.uid() and c.request_id=herco_save_booked_services_configured.request_id;
 if found then
  if previous.service_codes is distinct from selected or previous.after_options is distinct from normalized or previous.revision-1<>expected_revision then raise exception 'This request belongs to another edit.' using errcode='22023';end if;
  return public.herco_booked_services(booking.id);
 end if;
 if not editable or booking.service_revision<>expected_revision then raise exception 'The booking changed or cannot be edited. Reload before retrying.' using errcode='40001';end if;
 old_lines:=coalesce(booking.current_services,booking.original_services);old_options:=coalesce(booking.current_coating_options,booking.coating_options);
 select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('code',c.code,'label',c.label,'price_centavos',c.price_centavos,'max_centavos',c.max_centavos,'quote_required',case when c.quote_required then true end,'promotion',c.promotion)) order by c.code) into new_lines from public.herco_catalog() c where c.code=any(selected) and extract(dow from booking.visit_date)::smallint=any(c.appointment_days);
 if coalesce(jsonb_array_length(new_lines),0)<>cardinality(selected) then raise exception 'A selected service is unavailable on the booked date.' using errcode='22023';end if;
 new_lines:=herco_private.coating_price_lines(new_lines,booking.bike,normalized);
 perform herco_private.require_unchanged_preview(new_lines,expected_price_fingerprint);
 if new_lines=old_lines and normalized=old_options then return public.herco_booked_services(booking.id);end if;
 update public.herco_bookings b set current_services=new_lines,current_total_centavos=herco_private.price_line_total(new_lines),current_coating_options=normalized,service_revision=b.service_revision+1 where b.id=booking.id;
 insert into herco_private.booking_service_changes(booking_id,actor_id,request_id,revision,service_codes,before_services,after_services,before_options,after_options)values(booking.id,auth.uid(),request_id,expected_revision+1,selected,old_lines,new_lines,old_options,normalized);
 insert into public.herco_booking_events(booking_id,actor_id,kind,to_status)values(booking.id,auth.uid(),'booking_services_updated',booking.status);
 return public.herco_booked_services(booking.id);
end $$;
revoke all on function public.herco_save_booked_services_configured(uuid,uuid,integer,text[],jsonb,text)from public,anon,authenticated;
grant execute on function public.herco_save_booked_services_configured(uuid,uuid,integer,text[],jsonb,text)to authenticated;

create function public.herco_create_staff_booking_configured(customer uuid,customer_email text,request_id uuid,visit_date date,visit_hour smallint,service_codes text[],bike text,customer_name text,customer_phone text,plate_number text default '',options jsonb default '{}',expected_price_fingerprint text default null,walk_in boolean default false)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare matched jsonb;booking public.herco_bookings;normalized jsonb;previous_options jsonb;payload jsonb;services jsonb;form_version text;event_id bigint;
begin
 matched:=public.herco_lookup_booking_customer(customer_email);
 if customer is null or (matched->>'id')::uuid is distinct from customer then raise exception 'Verified customer not found.' using errcode='P0002';end if;
 if request_id is null or coalesce(char_length(btrim(bike)),0) not between 1 and 120 or coalesce(char_length(btrim(customer_name)),0) not between 1 and 120 or coalesce(char_length(btrim(customer_phone)),0) not between 3 and 40 or char_length(coalesce(plate_number,''))>30 then raise exception 'Check the contact details and motorcycle.' using errcode='22023';end if;
 normalized:=herco_private.normalize_coating_options(options,service_codes,bike);
 perform pg_advisory_xact_lock(72001,hashtext(customer::text||':'||request_id::text));
 select b.coating_options into previous_options from public.herco_bookings b where b.customer_id=customer and b.request_id=herco_create_staff_booking_configured.request_id;
 if previous_options is not null and previous_options is distinct from normalized then raise exception 'This request belongs to different service options.' using errcode='22023';end if;
 if not walk_in then
  perform public.herco_create_staff_booking(customer,customer_email,request_id,visit_date,visit_hour,service_codes,bike,customer_name,customer_phone,plate_number);
  select b.* into strict booking from public.herco_bookings b where b.customer_id=customer and b.request_id=herco_create_staff_booking_configured.request_id;
 else
  if visit_date is distinct from (clock_timestamp() at time zone 'Asia/Manila')::date or visit_hour is not null then raise exception 'Walk-ins must be for today without a reserved hour.' using errcode='22023';end if;
  if cardinality(service_codes) is null or cardinality(service_codes) not between 1 and 20 or (select count(distinct code)from unnest(service_codes)code)<>cardinality(service_codes) then raise exception 'Choose each service once.' using errcode='22023';end if;
  payload:=jsonb_build_object('kind','walk_in','staff_actor_id',auth.uid(),'date',visit_date,'services',to_jsonb(service_codes),'bike',btrim(bike),'name',btrim(customer_name),'phone',btrim(customer_phone),'plate',btrim(coalesce(plate_number,'')));
  select b.* into booking from public.herco_bookings b where b.customer_id=customer and b.request_id=herco_create_staff_booking_configured.request_id;
  if found then
   if booking.request_payload is distinct from payload then raise exception 'This request belongs to another booking.' using errcode='22023';end if;
  else
   select f.version into form_version from herco_private.walk_in_forms f where active and signature_method='typed_name' for share;
   if form_version is null then raise exception 'The shop must configure its walk-in form.' using errcode='22023';end if;
   select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('code',c.code,'label',c.label,'price_centavos',c.price_centavos,'max_centavos',c.max_centavos,'quote_required',case when c.quote_required then true end,'promotion',c.promotion)) order by c.code)into services from public.herco_catalog()c where c.code=any(service_codes)and extract(dow from visit_date)::smallint=any(c.appointment_days);
   if coalesce(jsonb_array_length(services),0)<>cardinality(service_codes)then raise exception 'A selected service is unavailable today.' using errcode='22023';end if;
   insert into public.herco_bookings(customer_id,request_id,request_payload,visit_date,visit_hour,bike,customer_contact,original_services,original_total_centavos,booking_kind)
   values(customer,request_id,payload,visit_date,null,btrim(bike),jsonb_build_object('name',btrim(customer_name),'email',matched->>'email','phone',btrim(customer_phone),'plate',btrim(coalesce(plate_number,''))),services,herco_private.price_line_total(services),'walk_in')returning * into booking;
   perform public.herco_request_walk_in_intake(booking.id,form_version);
   insert into public.herco_booking_events(booking_id,actor_id,kind,to_status)values(booking.id,auth.uid(),'walk_in_submitted','pending')returning id into event_id;
   insert into herco_private.notification_outbox(event_id,template,recipient,payload)values(event_id,'walk_in_submitted',matched->>'email',jsonb_build_object('booking_id',booking.id,'visit_date',visit_date));
  end if;
 end if;
 if previous_options is null then booking:=herco_private.apply_configured_coating_prices(booking.id,normalized);perform herco_private.require_unchanged_preview(booking.original_services,expected_price_fingerprint);end if;
 return jsonb_build_object('id',booking.id,'reference','HG-'||booking.reference_no,'status',booking.status,'totalCentavos',booking.original_total_centavos,'intakeRequired',walk_in,'estimateOpen',exists(select 1 from jsonb_array_elements(booking.original_services)x where x->'quote_required'='true' or x?'max_centavos'));
end $$;
revoke all on function public.herco_create_staff_booking_configured(uuid,text,uuid,date,smallint,text[],text,text,text,text,jsonb,text,boolean)from public,anon,authenticated;
grant execute on function public.herco_create_staff_booking_configured(uuid,text,uuid,date,smallint,text[],text,text,text,text,jsonb,text,boolean)to authenticated;
notify pgrst,'reload schema';
commit;
