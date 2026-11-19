begin;

alter table public.herco_bookings
  add column booking_kind text not null default 'appointment' check (booking_kind in ('appointment', 'walk_in')),
  alter column visit_hour drop not null,
  add check ((booking_kind = 'walk_in') = (visit_hour is null));

drop index public.herco_active_booking_slot;
create unique index herco_active_booking_slot on public.herco_bookings (visit_date, visit_hour)
  where status <> 'cancelled' and visit_hour is not null;
create index herco_walk_in_queue on public.herco_bookings (visit_date, created_at, id)
  where booking_kind = 'walk_in' and status <> 'cancelled';

create function public.herco_walk_in_booking_form()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare form jsonb;
begin
  perform herco_private.walk_in_actor();
  select jsonb_build_object(
    'version', f.version, 'title', f.title, 'body', f.body, 'method', f.signature_method,
    'date', (statement_timestamp() at time zone 'Asia/Manila')::date
  ) into form
  from herco_private.walk_in_forms f where f.active and f.signature_method = 'typed_name';
  return form;
end
$$;

create function public.herco_create_walk_in_booking(
  p_request_id uuid, p_date date, p_service_codes text[], p_bike text, p_name text, p_phone text,
  p_plate text, p_form_version text, p_signer_name text, p_acknowledged boolean
)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  actor uuid := herco_private.walk_in_actor();
  service_codes text[];
  bike text := btrim(coalesce(p_bike, ''));
  full_name text := btrim(coalesce(p_name, ''));
  phone text := btrim(coalesce(p_phone, ''));
  plate text := btrim(coalesce(p_plate, ''));
  signer text := btrim(coalesce(p_signer_name, ''));
  email text;
  payload jsonb;
  booking public.herco_bookings;
  services jsonb;
  service_count integer;
  eligible boolean;
  total bigint;
  signed_at timestamptz;
  event_id bigint;
begin
  if p_request_id is null or p_date is null or not isfinite(p_date)
    or coalesce(cardinality(p_service_codes), 0) not between 1 and 20
    or char_length(bike) not between 1 and 120 or char_length(full_name) not between 1 and 120
    or char_length(phone) not between 3 and 40 or char_length(plate) > 30
    or coalesce(char_length(p_form_version), 0) not between 1 and 60 then
    raise exception 'Check your contact, service selection, and walk-in form.' using errcode = '22023';
  end if;
  if p_acknowledged is distinct from true or lower(signer) <> lower(full_name) then
    raise exception 'Acknowledge the form and type the same full name shown in your contact details.' using errcode = '22023';
  end if;
  select array_agg(distinct code order by code) into service_codes from unnest(p_service_codes) code;
  if cardinality(service_codes) <> cardinality(p_service_codes) or array_position(service_codes, null) is not null then
    raise exception 'Choose each service once.' using errcode = '22023';
  end if;
  payload := jsonb_build_object('kind', 'walk_in', 'date', p_date, 'services', service_codes,
    'name', full_name, 'phone', phone, 'plate', plate, 'bike', bike, 'form_version', p_form_version);

  perform pg_advisory_xact_lock(72001, hashtext(actor::text || ':' || p_request_id::text));
  select b.* into booking from public.herco_bookings b where b.customer_id = actor and b.request_id = p_request_id;
  if found then
    if booking.request_payload is distinct from payload then
      raise exception 'This request ID belongs to a different booking.' using errcode = '22023';
    end if;
    return jsonb_build_object('id', booking.id, 'status', booking.status, 'totalCentavos', booking.original_total_centavos,
      'estimateOpen', exists (select 1 from jsonb_array_elements(booking.original_services) s
        where s->'quote_required' = 'true'::jsonb or jsonb_typeof(s->'max_centavos') = 'number'));
  end if;

  if not exists (
    select 1 from herco_private.walk_in_forms f
    where f.version = p_form_version and f.active and f.signature_method = 'typed_name' for share
  ) then
    raise exception 'The approved walk-in form changed or is unavailable. Reload before signing.' using errcode = '23P01';
  end if;
  signed_at := clock_timestamp();
  if p_date <> (signed_at at time zone 'Asia/Manila')::date then
    raise exception 'The shop date changed. Reload today’s walk-in form.' using errcode = '23P01';
  end if;
  select u.email into email from auth.users u where u.id = actor and u.email_confirmed_at is not null for share;
  if email is null then raise exception 'Verify your email before booking.' using errcode = '42501'; end if;

  -- The existing booking insert trigger applies the current promotion once.
  select count(*), sum(s.price_centavos), bool_and(extract(dow from p_date)::smallint = any(s.appointment_days)),
    jsonb_agg(jsonb_build_object('code', s.code, 'label', s.label, 'price_centavos', s.price_centavos) order by s.code)
  into service_count, total, eligible, services
  from herco_private.services s where s.enabled and s.code = any(service_codes);
  if service_count <> cardinality(service_codes) or eligible is not true then
    raise exception 'One or more selected services are unavailable today.' using errcode = '22023';
  end if;

  insert into public.herco_bookings(customer_id, request_id, request_payload, visit_date, visit_hour,
    bike, customer_contact, original_services, original_total_centavos, booking_kind)
  values (actor, p_request_id, payload, p_date, null, bike,
    jsonb_build_object('name', full_name, 'email', email, 'phone', phone, 'plate', plate),
    services, total, 'walk_in')
  returning * into booking;
  insert into herco_private.walk_in_intakes(booking_id, form_version, requested_by, requested_at,
    signer_user_id, signer_name, signed_at, acknowledged)
  values (booking.id, p_form_version, actor, signed_at, actor, signer, signed_at, true);
  insert into public.herco_booking_events(booking_id, actor_id, kind, to_status)
  values (booking.id, actor, 'walk_in_submitted', 'pending') returning id into event_id;
  insert into public.herco_booking_events(booking_id, actor_id, kind, to_status)
  values (booking.id, actor, 'walk_in_intake_signed', 'pending');
  insert into herco_private.notification_outbox(event_id, template, recipient, payload)
  values (event_id, 'walk_in_submitted', email, jsonb_build_object('booking_id', booking.id, 'visit_date', p_date));
  return jsonb_build_object('id', booking.id, 'status', booking.status, 'totalCentavos', booking.original_total_centavos,
    'estimateOpen', exists (select 1 from jsonb_array_elements(booking.original_services) s
      where s->'quote_required' = 'true'::jsonb or jsonb_typeof(s->'max_centavos') = 'number'));
end
$$;

revoke all on function public.herco_walk_in_booking_form(),
  public.herco_create_walk_in_booking(uuid, date, text[], text, text, text, text, text, text, boolean)
  from public, anon, authenticated;
grant execute on function public.herco_walk_in_booking_form(),
  public.herco_create_walk_in_booking(uuid, date, text[], text, text, text, text, text, text, boolean)
  to authenticated;

create or replace function public.herco_confirm_booking(booking_id uuid, approval_note text default '')
returns void
language plpgsql volatile security definer set search_path = '' as $$
declare
  grants text[] := herco_private.staff_booking_grants();
  booking public.herco_bookings;
  event_id bigint;
  note text := btrim(coalesce(approval_note, ''));
begin
  if ('confirmBooking' = any (grants)) is not true then
    raise exception 'You do not have permission to confirm bookings.' using errcode = '42501';
  end if;
  if booking_id is null or char_length(note) > 500 then
    raise exception 'Check the booking reference and private note.' using errcode = '22023';
  end if;
  select b.* into booking from public.herco_bookings b
    where b.id = herco_confirm_booking.booking_id for update;
  if not found then
    raise exception 'This booking could not be found.' using errcode = 'P0002';
  end if;
  if booking.status = 'confirmed' then return; end if;
  if booking.booking_kind = 'walk_in' and (booking.visit_date <> (clock_timestamp() at time zone 'Asia/Manila')::date
    or not exists (select 1 from herco_private.walk_in_intakes i where i.booking_id = booking.id and i.signed_at is not null)) then
    raise exception 'Only today’s signed walk-in can be confirmed.' using errcode = '23P01';
  end if;
  if booking.status <> 'pending' then
    raise exception 'This booking is no longer pending.' using errcode = '23P01';
  end if;

  -- A pending booking already owns this slot. Later availability blocks only
  -- restrict new reservations, so confirmation preserves the existing visit.
  update public.herco_bookings set status = 'confirmed' where id = booking.id;
  if note <> '' then
    insert into herco_private.booking_approval_notes values (booking.id, note);
  end if;
  insert into public.herco_booking_events (booking_id, actor_id, kind, to_status)
  values (booking.id, auth.uid(), 'booking_confirmed', 'confirmed')
  returning id into event_id;
  insert into herco_private.notification_outbox (event_id, template, recipient, payload)
  values (event_id, case when booking.booking_kind = 'walk_in' then 'walk_in_confirmed' else 'booking_confirmed' end,
    booking.customer_contact->>'email', jsonb_build_object(
    'booking_id', booking.id, 'visit_date', booking.visit_date, 'visit_hour', booking.visit_hour));
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
  if kind = 'reschedule' and (target_date < shop_now::date or target_date > shop_now::date + 20
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

create or replace function herco_private.may_edit_booked_services(booking public.herco_bookings)
returns boolean language plpgsql volatile set search_path = '' as $$
declare
  is_staff boolean;
  shop_now timestamp := clock_timestamp() at time zone 'Asia/Manila';
begin
  if auth.uid() is null then
    raise exception 'Sign in to see the booking services.' using errcode = '42501';
  end if;
  if (auth.jwt()->>'aal') = 'aal2' then
    perform 1 from herco_private.staff_memberships s where s.user_id = auth.uid() and s.enabled
      and 'Bookings' = any(s.page_grants) and 'editServices' = any(s.action_grants) for share;
    is_staff := found;
  end if;
  if booking.customer_id is distinct from auth.uid() and is_staff is not true then
    raise exception 'You do not have access to these booking services.' using errcode = '42501';
  end if;
  return booking.status = 'pending' and case when booking.booking_kind = 'walk_in' then booking.visit_date = shop_now::date
      else booking.visit_date + make_time(booking.visit_hour, 0, 0) > shop_now end
    or (is_staff is true and booking.status in ('pending', 'confirmed') and booking.visit_date >= shop_now::date);
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
    if target_date > shop_now::date + 20 or herco_private.slot_status(target_date, target_hour, shop_now) <> 'open'
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

commit;
