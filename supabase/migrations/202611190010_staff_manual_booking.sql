-- Staff and customers share one reservation, pricing, and idempotency transaction.
begin;

create function herco_private.create_booking_for(
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
  if visit_date < shop_now::date or visit_date > shop_now::date + 20
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

create or replace function public.herco_create_booking(
  request_id uuid, visit_date date, visit_hour smallint, service_codes text[], bike text,
  customer_name text, customer_phone text, plate_number text default ''
)
returns public.herco_bookings
language sql volatile security definer set search_path = '' as $$
  select b.* from herco_private.create_booking_for(auth.uid(), auth.uid(), false,
    request_id, visit_date, visit_hour, service_codes, bike, customer_name, customer_phone, plate_number) b;
$$;

create function herco_private.require_manual_booking_grant()
returns void
language plpgsql volatile set search_path = '' as $$
begin
  if ('createBooking' = any (herco_private.staff_booking_grants())) is not true then
    raise exception 'You do not have permission to create bookings for customers.' using errcode = '42501';
  end if;
end
$$;

create function public.herco_lookup_booking_customer(customer_email text)
returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  normalized text := lower(btrim(customer_email));
  candidate record;
  matching_customer jsonb;
begin
  perform herco_private.require_manual_booking_grant();
  if coalesce(char_length(normalized), 0) not between 3 and 254 then
    raise exception 'Enter the customer''s complete email address.' using errcode = '22023';
  end if;

  -- A missing or ambiguous match gives the same response. Never search by prefix.
  for candidate in select u.id, u.email from auth.users u
    where lower(u.email) = normalized and u.email_confirmed_at is not null limit 2
  loop
    if matching_customer is not null then return null; end if;
    matching_customer := jsonb_build_object('id', candidate.id, 'email', candidate.email);
  end loop;
  return matching_customer;
end
$$;

create function public.herco_create_staff_booking(
  customer uuid, customer_email text, request_id uuid, visit_date date, visit_hour smallint,
  service_codes text[], bike text, customer_name text, customer_phone text, plate_number text default ''
)
returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  matching_customer jsonb;
  booking public.herco_bookings;
begin
  matching_customer := public.herco_lookup_booking_customer(customer_email);
  if customer is null or (matching_customer->>'id')::uuid is distinct from customer then
    raise exception 'This verified customer match is no longer available. Search for the exact email again.' using errcode = 'P0002';
  end if;

  -- Hold the matched account so the address cannot change during reservation.
  perform 1 from auth.users u where u.id = customer and u.email = matching_customer->>'email'
    and u.email_confirmed_at is not null for share;
  if not found then
    raise exception 'This verified customer match is no longer available. Search for the exact email again.' using errcode = 'P0002';
  end if;

  booking := herco_private.create_booking_for(auth.uid(), customer, true, request_id,
    visit_date, visit_hour, service_codes, bike, customer_name, customer_phone, plate_number);
  return jsonb_build_object('id', booking.id, 'status', booking.status, 'totalCentavos', booking.original_total_centavos);
end
$$;

revoke all on function herco_private.create_booking_for(uuid, uuid, boolean, uuid, date, smallint, text[], text, text, text, text),
  herco_private.require_manual_booking_grant(), public.herco_lookup_booking_customer(text),
  public.herco_create_staff_booking(uuid, text, uuid, date, smallint, text[], text, text, text, text)
  from public, anon, authenticated;
grant execute on function public.herco_lookup_booking_customer(text),
  public.herco_create_staff_booking(uuid, text, uuid, date, smallint, text[], text, text, text, text)
  to authenticated;

commit;
