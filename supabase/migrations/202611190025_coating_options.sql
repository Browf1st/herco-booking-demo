begin;

alter table public.herco_bookings
  add column coating_options jsonb not null default '{}' check (jsonb_typeof(coating_options) = 'object');

create function herco_private.normalize_coating_options(options jsonb, service_codes text[], bike text)
returns jsonb
language plpgsql immutable set search_path = '' as $$
declare
  allowed_parts text[] := array['Wheels / mags', 'Frame', 'Subframe', 'Swingarm', 'Brackets', 'Foot pegs',
    'Grab rails', 'Metal covers', 'Other metal parts', 'Handlebar / grab bar', 'Brake lever',
    'Radiator cover / housing', 'Muffler cover', 'Gear cover', 'Side stand', 'Center stand', 'Caliper',
    'Shock springs (pair)', 'Front shocks (pair)', 'Crankcase', 'Crankcase (custom / two-tone)'];
  result jsonb := '{}'::jsonb;
  finish text;
  parts text[];
  front text;
  rear text;
begin
  if options is null then return result; end if;
  if jsonb_typeof(options) <> 'object' or exists (
    select 1 from jsonb_object_keys(options) as k
    where k not in ('ceramic_finish', 'red_body', 'powder_parts', 'wheel_front', 'wheel_rear')
  ) then raise exception 'Check the coating details.' using errcode = '22023'; end if;

  if options ? 'ceramic_finish' then
    finish := options->>'ceramic_finish';
    if ('ceramic' = any(service_codes)) is not true or jsonb_typeof(options->'ceramic_finish') <> 'string'
      or finish not in ('Stay Matte', 'Matte to Glossy', 'Enhance', 'Glossy Finish') then
      raise exception 'Choose a valid ceramic finish.' using errcode = '22023';
    end if;
    if finish = 'Enhance' then
      if (options->'red_body') is distinct from 'true'::jsonb
        or coalesce(btrim(bike), '') !~* '^honda[[:space:]]+(adv|pcx)[[:space:]]*(150|160)([^[:alnum:]_]|$)' then
        raise exception 'Enhance is for red Honda ADV or PCX 150/160 units.' using errcode = '22023';
      end if;
      result := result || jsonb_build_object('red_body', true);
    end if;
    result := result || jsonb_build_object('ceramic_finish', finish);
  end if;
  if options ? 'red_body' and finish is distinct from 'Enhance' then
    raise exception 'Red body confirmation is only needed for Enhance.' using errcode = '22023';
  end if;

  if options ? 'powder_parts' then
    if ('wheel-colour' = any(service_codes)) is not true or jsonb_typeof(options->'powder_parts') <> 'array' then
      raise exception 'Choose valid powder coating parts.' using errcode = '22023';
    end if;
    if jsonb_array_length(options->'powder_parts') not between 1 and cardinality(allowed_parts)
      or exists (select 1 from jsonb_array_elements(options->'powder_parts') as item
        where jsonb_typeof(item) <> 'string' or ((item#>>'{}') = any(allowed_parts)) is not true) then
      raise exception 'Choose valid powder coating parts.' using errcode = '22023';
    end if;
    select array_agg(distinct option order by option) into parts
    from jsonb_array_elements_text(options->'powder_parts') as option;
    result := result || jsonb_build_object('powder_parts', parts);
  end if;

  if ('Wheels / mags' = any(parts)) is true then
    front := options->>'wheel_front';
    rear := options->>'wheel_rear';
    if (front is null and rear is null)
      or (options ? 'wheel_front' and (jsonb_typeof(options->'wheel_front') <> 'string'
        or front !~ '^(Not sure|1[0-9]|2[0-2])$'))
      or (options ? 'wheel_rear' and (jsonb_typeof(options->'wheel_rear') <> 'string'
        or rear !~ '^(Not sure|1[0-9]|2[0-2])$')) then
      raise exception 'Enter a wheel size or choose Not sure.' using errcode = '22023';
    end if;
    result := result || jsonb_strip_nulls(jsonb_build_object('wheel_front', front, 'wheel_rear', rear));
  elsif options ? 'wheel_front' or options ? 'wheel_rear' then
    raise exception 'Wheel sizes only apply to a selected wheel or mag.' using errcode = '22023';
  end if;
  return result;
end;
$$;

create function public.herco_create_booking_configured(
  request_id uuid, visit_date date, visit_hour smallint, service_codes text[], bike text,
  customer_name text, customer_phone text, plate_number text default '', options jsonb default '{}'
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
  normalized := herco_private.normalize_coating_options(options, service_codes, bike);

  -- Use the same retry lock as create_booking_for and bind a replay to the original options.
  perform pg_advisory_xact_lock(72001, hashtext(actor::text || ':' || request_id::text));
  select b.coating_options into previous_options from public.herco_bookings as b
  where b.customer_id = actor and b.request_id = herco_create_booking_configured.request_id;
  if previous_options is not null and previous_options is distinct from normalized then
    raise exception 'This request ID belongs to different coating details.' using errcode = '22023';
  end if;
  booking := public.herco_create_booking(request_id, visit_date, visit_hour, service_codes,
    bike, customer_name, customer_phone, plate_number);
  if previous_options is null and normalized <> '{}'::jsonb then
    booking := herco_private.apply_configured_coating_prices(booking.id,normalized);
  end if;
  return booking;
end;
$$;

create function public.herco_staff_booking_day_with_options(visit_date date)
returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  result jsonb := public.herco_staff_booking_day(visit_date);
  bookings jsonb;
begin
  -- The original staff projection checks MFA and the Bookings grant.
  select coalesce(jsonb_agg(item.booking || jsonb_build_object('coating_options', stored.coating_options)
    order by item.position), '[]'::jsonb) into bookings
  from jsonb_array_elements(result->'bookings') with ordinality as item(booking, position)
  join public.herco_bookings as stored on stored.id = (item.booking->>'id')::uuid;
  return jsonb_set(result, '{bookings}', bookings);
end;
$$;

revoke all on function herco_private.normalize_coating_options(jsonb, text[], text),
  public.herco_create_booking_configured(uuid, date, smallint, text[], text, text, text, text, jsonb),
  public.herco_staff_booking_day_with_options(date) from public, anon, authenticated;
grant execute on function public.herco_create_booking_configured(uuid, date, smallint, text[], text, text, text, text, jsonb),
  public.herco_staff_booking_day_with_options(date) to authenticated;

commit;
