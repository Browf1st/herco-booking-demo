begin;

create function herco_private.coating_price_lines(base_lines jsonb, bike text, options jsonb)
returns jsonb language plpgsql stable set search_path = '' as $$
declare
  rule herco_private.coating_price_rules;
  promo herco_private.booking_promotion;
  line jsonb;
  matched jsonb;
  code text;
  lines jsonb := '[]';
  discount integer;
  maximum integer;
begin
  select p.* into promo from herco_private.booking_promotion p where p.singleton and p.enabled;
  for line in select value from jsonb_array_elements(base_lines) loop
    code := line->>'code';
    matched := case code
      when 'ceramic' then options - array['powder_parts','wheel_front','wheel_rear']
      when 'wheel-colour' then options - array['ceramic_finish','red_body']
      else '{}'::jsonb end;
    select r.* into rule from herco_private.coating_price_rules r
      where r.enabled and r.service_code=code and r.option_match=matched
        and r.bike_key in ('',lower(btrim(bike)))
      order by (r.bike_key <> '') desc limit 1;
    if found then
      discount := herco_private.pricing_discount(rule.minimum_centavos,coalesce(promo.discount_basis_points,0));
      maximum := rule.maximum_centavos-herco_private.pricing_discount(rule.maximum_centavos,coalesce(promo.discount_basis_points,0));
      line := (line - array['price_centavos','max_centavos','quote_required','promotion']) ||
        jsonb_strip_nulls(jsonb_build_object(
          'price_centavos',rule.minimum_centavos-discount,'max_centavos',maximum,
          'quote_required',case when rule.quote_required then true end,
          'promotion',herco_private.promotion_snapshot(promo,rule.minimum_centavos,discount),
          'coating_rule_id',rule.id
        ));
    end if;
    lines := lines || jsonb_build_array(line);
  end loop;
  return lines;
end;
$$;

create function herco_private.preview_price_lines(lines jsonb)
returns jsonb language sql immutable set search_path = '' as $$
  select coalesce(jsonb_agg(item - 'coating_rule_id' order by item->>'code'), '[]'::jsonb)
    from jsonb_array_elements(lines) item;
$$;

create function herco_private.price_line_total(lines jsonb)
returns bigint language sql immutable set search_path = '' as $$
  select coalesce(sum((item->>'price_centavos')::bigint),0) from jsonb_array_elements(lines) item;
$$;

create function herco_private.require_unchanged_preview(lines jsonb, expected text)
returns void language plpgsql immutable set search_path = '' as $$
begin
  if expected is not null and expected is distinct from md5(herco_private.preview_price_lines(lines)::text) then
    raise exception 'Service prices changed. Review the new estimate before submitting again.' using errcode = 'P0409';
  end if;
end;
$$;

create or replace function herco_private.apply_configured_coating_prices(booking_id uuid, options jsonb)
returns public.herco_bookings language plpgsql volatile set search_path = '' as $$
declare booking public.herco_bookings;
  lines jsonb;
begin
  select b.* into strict booking from public.herco_bookings b where b.id=booking_id for update;
  lines := herco_private.coating_price_lines(booking.original_services,booking.bike,options);
  update public.herco_bookings b set coating_options=options, original_services=lines,
    original_total_centavos=herco_private.price_line_total(lines)
    where b.id=booking_id returning b.* into booking;
  return booking;
end;
$$;

create function public.herco_preview_coating_price(bike text, service_codes text[], options jsonb default '{}')
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  normalized jsonb;
  lines jsonb;
begin
  if auth.uid() is null or not exists (
    select 1 from auth.users u where u.id=auth.uid() and u.email_confirmed_at is not null
  ) then raise exception 'Verify your email before preparing a booking.' using errcode = '42501'; end if;

  if coalesce(char_length(btrim(bike)),0) not between 1 and 120
    or coalesce(cardinality(service_codes),0) not between 1 and 20
    or (select count(distinct code) from unnest(service_codes) code) <> cardinality(service_codes) then
    raise exception 'Check the bike and selected services.' using errcode = '22023';
  end if;
  normalized := herco_private.normalize_coating_options(options,service_codes,bike);

  select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
    'code',c.code,'label',c.label,'price_centavos',c.price_centavos,'max_centavos',c.max_centavos,
    'quote_required',case when c.quote_required then true end,'promotion',c.promotion
  )) order by c.code) into lines from public.herco_catalog() c where c.code=any(service_codes);
  if coalesce(jsonb_array_length(lines),0) <> cardinality(service_codes) then
    raise exception 'One or more selected services are unavailable.' using errcode = '22023';
  end if;

  lines := herco_private.preview_price_lines(herco_private.coating_price_lines(lines,bike,normalized));
  return jsonb_build_object('lines',lines,'totalCentavos',herco_private.price_line_total(lines),
    'fingerprint',md5(lines::text));
end;
$$;

drop function public.herco_create_booking_configured(uuid,date,smallint,text[],text,text,text,text,jsonb);
create function public.herco_create_booking_configured(
  request_id uuid, visit_date date, visit_hour smallint, service_codes text[], bike text,
  customer_name text, customer_phone text, plate_number text default '', options jsonb default '{}',
  expected_price_fingerprint text default null
)
returns public.herco_bookings
language plpgsql volatile security definer set search_path = '' as $$
declare
  actor uuid := auth.uid();
  normalized jsonb;
  previous_options jsonb;
  booking public.herco_bookings;
begin
  if actor is null then raise exception 'Sign in before booking.' using errcode = '42501'; end if;
  if request_id is null then raise exception 'Choose a booking request ID.' using errcode = '22023'; end if;
  normalized := herco_private.normalize_coating_options(options,service_codes,bike);
  perform pg_advisory_xact_lock(72001,hashtext(actor::text || ':' || request_id::text));
  select b.coating_options into previous_options from public.herco_bookings b
    where b.customer_id=actor and b.request_id=herco_create_booking_configured.request_id;
  if previous_options is not null and previous_options is distinct from normalized then
    raise exception 'This request ID belongs to different coating details.' using errcode = '22023';
  end if;
  booking := public.herco_create_booking(request_id,visit_date,visit_hour,service_codes,
    bike,customer_name,customer_phone,plate_number);
  if previous_options is null then
    if normalized <> '{}'::jsonb then
      booking := herco_private.apply_configured_coating_prices(booking.id,normalized);
    end if;
    perform herco_private.require_unchanged_preview(booking.original_services,expected_price_fingerprint);
  end if;
  return booking;
end;
$$;

drop function public.herco_create_walk_in_booking_configured(uuid,date,text[],text,text,text,text,text,text,boolean,jsonb);
create function public.herco_create_walk_in_booking_configured(
  p_request_id uuid, p_date date, p_service_codes text[], p_bike text, p_name text, p_phone text,
  p_plate text, p_form_version text, p_signer_name text, p_acknowledged boolean, p_options jsonb default '{}',
  p_expected_price_fingerprint text default null
)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  actor uuid := herco_private.walk_in_actor();
  normalized jsonb;
  previous_options jsonb;
  receipt jsonb;
  booking public.herco_bookings;
begin
  if p_request_id is null then raise exception 'Choose a booking request ID.' using errcode = '22023'; end if;
  normalized := herco_private.normalize_coating_options(p_options,p_service_codes,p_bike);
  perform pg_advisory_xact_lock(72001,hashtext(actor::text || ':' || p_request_id::text));
  select b.coating_options into previous_options from public.herco_bookings b
    where b.customer_id=actor and b.request_id=p_request_id;
  if previous_options is not null and previous_options is distinct from normalized then
    raise exception 'This request ID belongs to different coating details.' using errcode = '22023';
  end if;
  receipt := public.herco_create_walk_in_booking(p_request_id,p_date,p_service_codes,p_bike,p_name,p_phone,
    p_plate,p_form_version,p_signer_name,p_acknowledged);
  if previous_options is null then
    if normalized <> '{}'::jsonb then
      booking := herco_private.apply_configured_coating_prices((receipt->>'id')::uuid,normalized);
      receipt := receipt || jsonb_build_object('totalCentavos',booking.original_total_centavos,
        'estimateOpen',exists (select 1 from jsonb_array_elements(booking.original_services) line
          where line->'quote_required'='true'::jsonb or jsonb_typeof(line->'max_centavos')='number'));
    else
      select b.* into strict booking from public.herco_bookings b where b.id=(receipt->>'id')::uuid;
    end if;
    perform herco_private.require_unchanged_preview(booking.original_services,p_expected_price_fingerprint);
  end if;
  return receipt;
end;
$$;

revoke all on function herco_private.coating_price_lines(jsonb,text,jsonb),
  herco_private.preview_price_lines(jsonb), herco_private.price_line_total(jsonb),
  herco_private.require_unchanged_preview(jsonb,text),
  public.herco_preview_coating_price(text,text[],jsonb),
  public.herco_create_booking_configured(uuid,date,smallint,text[],text,text,text,text,jsonb,text),
  public.herco_create_walk_in_booking_configured(uuid,date,text[],text,text,text,text,text,text,boolean,jsonb,text)
  from public, anon, authenticated;
grant execute on function public.herco_preview_coating_price(text,text[],jsonb),
  public.herco_create_booking_configured(uuid,date,smallint,text[],text,text,text,text,jsonb,text),
  public.herco_create_walk_in_booking_configured(uuid,date,text[],text,text,text,text,text,text,boolean,jsonb,text)
  to authenticated;

commit;
