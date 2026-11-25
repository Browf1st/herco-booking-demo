begin;

alter table public.herco_bookings
  alter column customer_id drop not null,
  add column guest_staff_actor_id uuid,
  add constraint herco_booking_guest_ownership check (
    (customer_id is not null and guest_staff_actor_id is null)
    or (customer_id is null and guest_staff_actor_id is not null
      and booking_kind = 'appointment'
      and not (customer_contact ? 'email'))
  );

create unique index herco_staff_guest_request
  on public.herco_bookings (guest_staff_actor_id, request_id)
  where guest_staff_actor_id is not null;

-- Staff confirmation, cancellation and rescheduling still write their audit
-- events. Those functions use the outbox for customers with an email address.
create function herco_private.skip_guest_booking_notification()
returns trigger language plpgsql volatile set search_path = '' as $$
begin
  if new.recipient is null and exists (
    select 1 from public.herco_booking_events e
    join public.herco_bookings b on b.id = e.booking_id
    where e.id = new.event_id and b.guest_staff_actor_id is not null
  ) then
    return null;
  end if;
  return new;
end
$$;

revoke all on function herco_private.skip_guest_booking_notification() from public, anon, authenticated;
create trigger herco_skip_guest_booking_notification
before insert on herco_private.notification_outbox
for each row execute function herco_private.skip_guest_booking_notification();

create function public.herco_create_staff_guest_booking(
  request_id uuid, visit_date date, visit_hour smallint, service_codes text[],
  bike text, customer_name text, customer_phone text default '', plate_number text default '',
  options jsonb default '{}', expected_price_fingerprint text default null
)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  actor uuid := auth.uid();
  name text := customer_name;
  phone text := btrim(coalesce(customer_phone, ''));
  plate text := btrim(coalesce(plate_number, ''));
  motorcycle text := btrim(bike);
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

  if request_id is null or visit_date is null or not isfinite(visit_date)
    or visit_hour is null or visit_hour not between 0 and 23
    or coalesce(cardinality(service_codes), 0) not between 1 and 20
    or coalesce(char_length(motorcycle), 0) not between 1 and 120
    or coalesce(char_length(name), 0) not between 1 and 120
    or name !~ '[^[:space:]]'
    or (phone <> '' and (phone !~ '^\+?[0-9 ()-]{7,20}$'
      or char_length(regexp_replace(phone, '[^0-9]', '', 'g')) not between 7 and 15))
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

  perform pg_advisory_xact_lock(72001, hashtext('guest:' || actor::text || ':' || request_id::text));
  select b.* into booking from public.herco_bookings b
  where b.guest_staff_actor_id = actor and b.request_id = herco_create_staff_guest_booking.request_id;

  if found then
    if booking.request_payload is distinct from request_data then
      raise exception 'This request ID belongs to a different booking.' using errcode = '22023';
    end if;
  else
    shop_now := clock_timestamp() at time zone 'Asia/Manila';
    if visit_date not between shop_now::date and shop_now::date + 365 then
      raise exception 'That appointment time is unavailable. Choose another slot.' using errcode = '23P01';
    end if;

    -- Share the day lock with other booking and availability writers.
    perform pg_advisory_xact_lock(72002, visit_date - date '2000-01-01');
    shop_now := clock_timestamp() at time zone 'Asia/Manila';
    if herco_private.slot_status(visit_date, visit_hour, shop_now) <> 'open' then
      raise exception 'That appointment time is unavailable. Choose another slot.' using errcode = '23P01';
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

    insert into public.herco_bookings (
      guest_staff_actor_id, request_id, request_payload, visit_date, visit_hour,
      bike, customer_contact, original_services, original_total_centavos
    ) values (
      actor, request_id, request_data, visit_date, visit_hour, motorcycle,
      jsonb_build_object('name', name, 'phone', phone, 'plate', plate), services, total
    ) returning * into booking;

    booking := herco_private.apply_configured_coating_prices(booking.id, normalized_options);
    perform herco_private.require_unchanged_preview(booking.original_services, expected_price_fingerprint);

    insert into public.herco_booking_events (booking_id, actor_id, kind, to_status)
    values (booking.id, actor, 'booking_created_by_staff', 'pending');
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

-- The existing intake requires a verified booking owner.
create or replace function public.herco_walk_in_intake(p_booking_id uuid)
returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  actor uuid := herco_private.walk_in_actor();
  staff boolean := herco_private.can_request_walk_in_intake(false);
  booking public.herco_bookings;
  form herco_private.walk_in_forms;
  intake herco_private.walk_in_intakes;
  customer boolean;
  state text;
begin
  select b.* into booking from public.herco_bookings b
  where b.id = p_booking_id and (staff or b.customer_id = actor);
  if not found then
    raise exception 'This booking is unavailable to your account.' using errcode = 'P0002';
  end if;
  customer := booking.customer_id is not distinct from actor;

  select i.* into intake from herco_private.walk_in_intakes i
  where i.booking_id = booking.id and i.signed_at is not null;
  if booking.customer_id is null then
    state := 'unavailable';
  elsif found then
    select f.* into form from herco_private.walk_in_forms f where f.version = intake.form_version;
    state := 'signed';
  elsif booking.status not in ('pending', 'confirmed') then
    state := 'closed';
  else
    select f.* into form from herco_private.walk_in_forms f where f.active;
    if not found then
      state := 'unavailable';
    else
      select i.* into intake from herco_private.walk_in_intakes i
      where i.booking_id = booking.id and i.form_version = form.version;
      state := case when found then 'awaiting_signature' else 'awaiting_request' end;
    end if;
  end if;

  return jsonb_build_object(
    'bookingId', booking.id, 'customerName', booking.customer_contact->>'name',
    'bike', booking.bike, 'date', booking.visit_date, 'hour', booking.visit_hour,
    'state', state, 'staff', staff, 'canRequest', staff and state = 'awaiting_request',
    'canSign', customer and state = 'awaiting_signature',
    'form', case when form.version is not null and (staff or state in ('awaiting_signature', 'signed')) then
      jsonb_build_object('version', form.version, 'title', form.title, 'body', form.body, 'method', form.signature_method)
    end,
    'signedAt', intake.signed_at, 'signerName', case when customer then intake.signer_name end
  );
end
$$;

create function herco_private.normalized_booking_name(name text)
returns text language sql immutable strict set search_path = '' as $$
  select nullif(lower(btrim(regexp_replace(name, '[[:space:]]+', ' ', 'g'))), '');
$$;

-- Supports exact-name lookup with newest visits first, including hour and stable tie-breakers.
create index herco_booking_normalized_name
  on public.herco_bookings (
    herco_private.normalized_booking_name(customer_contact->>'name'),
    visit_date desc, visit_hour desc nulls last, created_at desc, id desc
  );

create function public.herco_staff_booking_name_groups(
  p_surface text, p_query text default '', p_page integer default 1, p_name text default null
)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  query_key text := herco_private.normalized_booking_name(p_query);
  name_key text := herco_private.normalized_booking_name(p_name);
  result jsonb;
begin
  case p_surface
    when 'customers' then
      perform herco_private.require_customers_page();
    when 'history' then
      if not herco_private.has_verified_staff_session() then
        raise exception 'Staff access required.' using errcode = '42501';
      end if;
      perform 1 from herco_private.staff_memberships m
      where m.user_id = auth.uid() and m.enabled and m.page_grants && array['Booking history','Bookings']
      for share;
      if not found then
        raise exception 'You cannot access these booking records.' using errcode = '42501';
      end if;
    else
      raise exception 'Choose Customers or Booking History.' using errcode = '22023';
  end case;

  if p_page is null or p_page < 1
    or coalesce(char_length(p_query), 0) > 254 or coalesce(char_length(p_name), 0) > 254
    or (p_name is not null and name_key is null) then
    raise exception 'Check the name and page.' using errcode = '22023';
  end if;

  if name_key is not null then
    select jsonb_build_object(
      'name', coalesce((
        select b.customer_contact->>'name' from public.herco_bookings b
        where herco_private.normalized_booking_name(b.customer_contact->>'name') = name_key
        order by b.visit_date desc, b.visit_hour desc nulls last, b.created_at desc, b.id desc limit 1
      ), p_name),
      'total', (
        select count(*) from public.herco_bookings b
        where herco_private.normalized_booking_name(b.customer_contact->>'name') = name_key
      ),
      'bookings', coalesce(jsonb_agg(
        jsonb_build_object('id', b.id, 'reference', 'HG-' || b.reference_no, 'date', b.visit_date,
          'hour', b.visit_hour, 'status', b.status, 'bike', b.bike)
        order by b.visit_date desc, b.visit_hour desc nulls last, b.created_at desc, b.id desc
      ), '[]'::jsonb)
    ) into result
    from (
      select b.id, b.reference_no, b.visit_date, b.visit_hour, b.status, b.bike, b.created_at
      from public.herco_bookings b
      where herco_private.normalized_booking_name(b.customer_contact->>'name') = name_key
      order by b.visit_date desc, b.visit_hour desc nulls last, b.created_at desc, b.id desc
      offset (p_page::bigint - 1) * 20 limit 20
    ) b;
  else
    with named as (
      select b.customer_contact->>'name' as name, b.visit_date, b.visit_hour, b.created_at, b.id,
        herco_private.normalized_booking_name(b.customer_contact->>'name') as key
      from public.herco_bookings b
    ), names as (
      select distinct on (key) key, name, count(*) over (partition by key) as total
      from named
      where key is not null and (query_key is null or position(query_key in key) > 0)
      order by key, visit_date desc, visit_hour desc nulls last, created_at desc, id desc
    )
    select jsonb_build_object(
      'total', (select count(*) from names),
      'groups', coalesce(jsonb_agg(jsonb_build_object('name', page.name, 'total', page.total) order by page.key), '[]'::jsonb)
    ) into result
    from (select * from names order by key offset (p_page::bigint - 1) * 20 limit 20) page;
  end if;

  return result;
end
$$;

revoke all on function herco_private.normalized_booking_name(text),
  public.herco_create_staff_guest_booking(uuid, date, smallint, text[], text, text, text, text, jsonb, text),
  public.herco_staff_booking_name_groups(text, text, integer, text) from public, anon, authenticated;
grant execute on function
  public.herco_create_staff_guest_booking(uuid, date, smallint, text[], text, text, text, text, jsonb, text),
  public.herco_staff_booking_name_groups(text, text, integer, text) to authenticated;

notify pgrst, 'reload schema';
commit;
