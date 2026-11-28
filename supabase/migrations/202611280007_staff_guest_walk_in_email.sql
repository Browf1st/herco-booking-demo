begin;

-- Guest bookings may now be same-day walk-ins and may record an optional email.
-- The ownership rule keeps its meaning: a booking has either a verified account
-- or the staff member who recorded the guest, never both.
alter table public.herco_bookings drop constraint herco_booking_guest_ownership;
alter table public.herco_bookings add constraint herco_booking_guest_ownership check (
  (customer_id is not null and guest_staff_actor_id is null)
  or (customer_id is null and guest_staff_actor_id is not null
    and (not (customer_contact ? 'email') or jsonb_typeof(customer_contact->'email') = 'string'))
);

-- A guest with no email has an empty recipient. Skip it like the old null one.
create or replace function herco_private.skip_guest_booking_notification()
returns trigger language plpgsql volatile set search_path = '' as $$
begin
  if btrim(coalesce(new.recipient, '')) = '' and exists (
    select 1 from public.herco_booking_events e
    join public.herco_bookings b on b.id = e.booking_id
    where e.id = new.event_id and b.guest_staff_actor_id is not null
  ) then
    return null;
  end if;
  return new;
end
$$;

drop function public.herco_create_staff_guest_booking(uuid, date, smallint, text[], text, text, text, text, jsonb, text);

create function public.herco_create_staff_guest_booking(
  request_id uuid, visit_date date, visit_hour smallint, service_codes text[],
  bike text, customer_name text, customer_phone text default '', plate_number text default '',
  options jsonb default '{}', expected_price_fingerprint text default null,
  walk_in boolean default false, customer_email text default ''
)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  actor uuid := auth.uid();
  name text := customer_name;
  phone text := btrim(coalesce(customer_phone, ''));
  email text := btrim(coalesce(customer_email, ''));
  plate text := btrim(coalesce(plate_number, ''));
  motorcycle text := btrim(bike);
  is_walk_in boolean := coalesce(walk_in, false);
  selected_codes text[];
  normalized_options jsonb;
  request_data jsonb;
  booking public.herco_bookings;
  shop_now timestamp;
  services jsonb;
  service_count integer;
  total bigint;
begin
  perform herco_private.require_manual_booking_grant();

  -- A walk-in may omit the date: it is always today in the shop's time.
  if is_walk_in and visit_date is null then
    visit_date := (clock_timestamp() at time zone 'Asia/Manila')::date;
  end if;

  if request_id is null or visit_date is null or not isfinite(visit_date)
    or (is_walk_in and visit_hour is not null)
    or (not is_walk_in and (visit_hour is null or visit_hour not between 0 and 23))
    or coalesce(cardinality(service_codes), 0) not between 1 and 20
    or coalesce(char_length(motorcycle), 0) not between 1 and 120
    or coalesce(char_length(name), 0) not between 1 and 120
    or name !~ '[^[:space:]]'
    or (phone <> '' and (phone !~ '^\+?[0-9 ()-]{7,20}$'
      or char_length(regexp_replace(phone, '[^0-9]', '', 'g')) not between 7 and 15))
    or (email <> '' and (char_length(email) > 254 or email !~ '^[^[:space:]@]+@[^[:space:]@]+$'))
    or char_length(plate) > 30 then
    raise exception 'Check the visit, selected services and contact details.' using errcode = '22023';
  end if;

  select array_agg(distinct code order by code) into selected_codes from unnest(service_codes) as code;
  if cardinality(selected_codes) <> cardinality(service_codes) or array_position(selected_codes, null) is not null then
    raise exception 'Choose each service once.' using errcode = '22023';
  end if;

  normalized_options := herco_private.normalize_coating_options(options, selected_codes, motorcycle);
  request_data := jsonb_build_object(
    'date', visit_date, 'hour', visit_hour, 'bike', motorcycle, 'services', selected_codes,
    'name', name, 'phone', phone, 'plate', plate, 'options', normalized_options
  );
  -- Older saved requests have neither key, so a retry of one still matches.
  if is_walk_in then request_data := request_data || jsonb_build_object('walk_in', true); end if;
  if email <> '' then request_data := request_data || jsonb_build_object('email', email); end if;

  perform pg_advisory_xact_lock(72001, hashtext('guest:' || actor::text || ':' || request_id::text));
  select b.* into booking from public.herco_bookings b
  where b.guest_staff_actor_id = actor and b.request_id = herco_create_staff_guest_booking.request_id;

  if found then
    if booking.request_payload is distinct from request_data then
      raise exception 'This request ID belongs to a different booking.' using errcode = '22023';
    end if;
  else
    shop_now := clock_timestamp() at time zone 'Asia/Manila';
    if is_walk_in then
      -- Same rule as the verified-account walk-in: today in Manila, no reserved hour.
      if visit_date <> shop_now::date then
        raise exception 'Walk-ins must be for today without a reserved hour.' using errcode = '22023';
      end if;
    else
      if visit_date not between shop_now::date and shop_now::date + 365 then
        raise exception 'That appointment time is unavailable. Choose another slot.' using errcode = '23P01';
      end if;

      -- Share the day lock with other booking and availability writers.
      perform pg_advisory_xact_lock(72002, visit_date - date '2000-01-01');
      shop_now := clock_timestamp() at time zone 'Asia/Manila';
      if herco_private.slot_status(visit_date, visit_hour, shop_now) <> 'open' then
        raise exception 'That appointment time is unavailable. Choose another slot.' using errcode = '23P01';
      end if;
    end if;

    select count(*), sum(s.price_centavos),
      jsonb_agg(jsonb_build_object('code', s.code, 'label', s.label, 'price_centavos', s.price_centavos) order by s.code)
    into service_count, total, services
    from herco_private.services s
    where s.enabled and s.code = any(selected_codes)
      and extract(dow from visit_date)::smallint = any(s.appointment_days);
    if service_count <> cardinality(selected_codes) then
      raise exception 'One or more services are unavailable on that date.' using errcode = '22023';
    end if;

    -- A guest has no account to sign the digital intake, so a guest walk-in is
    -- booked directly as confirmed. It never creates an intake record.
    insert into public.herco_bookings (
      guest_staff_actor_id, request_id, request_payload, visit_date, visit_hour,
      bike, customer_contact, original_services, original_total_centavos,
      booking_kind, status
    ) values (
      actor, request_id, request_data, visit_date, case when is_walk_in then null else visit_hour end, motorcycle,
      jsonb_build_object('name', name, 'phone', phone, 'email', email, 'plate', plate), services, total,
      case when is_walk_in then 'walk_in' else 'appointment' end,
      case when is_walk_in then 'confirmed' else 'pending' end
    ) returning * into booking;

    booking := herco_private.apply_configured_coating_prices(booking.id, normalized_options);
    perform herco_private.require_unchanged_preview(booking.original_services, expected_price_fingerprint);

    insert into public.herco_booking_events (booking_id, actor_id, kind, to_status)
    values (booking.id, actor, 'booking_created_by_staff', booking.status);
  end if;

  return jsonb_build_object(
    'id', booking.id, 'reference', 'HG-' || booking.reference_no, 'status', booking.status,
    'totalCentavos', booking.original_total_centavos, 'intakeRequired', false,
    'estimateOpen', exists (
      select 1 from jsonb_array_elements(booking.original_services) line
      where line->'quote_required' = 'true' or line ? 'max_centavos'
    )
  );
end
$$;

revoke all on function public.herco_create_staff_guest_booking(uuid, date, smallint, text[], text, text, text, text, jsonb, text, boolean, text)
  from public, anon, authenticated;
grant execute on function public.herco_create_staff_guest_booking(uuid, date, smallint, text[], text, text, text, text, jsonb, text, boolean, text)
  to authenticated;

notify pgrst, 'reload schema';
commit;
