begin;

alter table public.herco_bookings
  add column current_services jsonb check (jsonb_typeof(current_services) = 'array'),
  add column current_total_centavos bigint check (current_total_centavos >= 0),
  add column service_revision integer not null default 0 check (service_revision >= 0),
  add check ((current_services is null) = (current_total_centavos is null));

create table herco_private.booking_service_changes (
  booking_id uuid not null references public.herco_bookings(id),
  actor_id uuid not null references auth.users(id),
  request_id uuid not null,
  revision integer not null,
  service_codes text[] not null,
  before_services jsonb not null,
  after_services jsonb not null,
  recorded_at timestamptz not null default now(),
  primary key (booking_id, revision),
  unique (booking_id, actor_id, request_id)
);
alter table herco_private.booking_service_changes enable row level security;
revoke all on herco_private.booking_service_changes from public, anon, authenticated;

create function herco_private.may_edit_booked_services(booking public.herco_bookings)
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
  return booking.status = 'pending' and booking.visit_date + make_time(booking.visit_hour, 0, 0) > shop_now
    or (is_staff is true and booking.status in ('pending', 'confirmed') and booking.visit_date >= shop_now::date);
end
$$;

create function public.herco_booked_services(booking_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  booking public.herco_bookings;
  editable boolean;
begin
  select b.* into booking from public.herco_bookings b where b.id = booking_id;
  if not found then raise exception 'Booking not found.' using errcode = 'P0002'; end if;
  editable := herco_private.may_edit_booked_services(booking);
  return jsonb_build_object('original', booking.original_services, 'current', coalesce(booking.current_services, booking.original_services),
    'totalCentavos', coalesce(booking.current_total_centavos, booking.original_total_centavos),
    'revision', booking.service_revision, 'date', booking.visit_date, 'canEdit', editable,
    'changes', coalesce((select jsonb_agg(to_jsonb(h) order by h.revision desc) from (
      select c.revision, c.recorded_at, c.before_services, c.after_services
      from herco_private.booking_service_changes c where c.booking_id = booking.id
      order by c.revision desc limit 10
    ) h), '[]'::jsonb));
end
$$;

create function public.herco_save_booked_services(
  booking_id uuid, request_id uuid, expected_revision integer, service_codes text[]
)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  booking public.herco_bookings;
  previous herco_private.booking_service_changes;
  selected text[];
  editable boolean;
  old_lines jsonb;
  new_lines jsonb;
  total bigint;
  changed_at timestamptz := clock_timestamp();
begin
  if booking_id is null or request_id is null or expected_revision is null or expected_revision < 0
    or coalesce(cardinality(service_codes), 0) not between 1 and 20
    or array_position(service_codes, null) is not null then
    raise exception 'Choose between one and twenty services.' using errcode = '22023';
  end if;
  select array_agg(distinct code order by code) into selected from unnest(service_codes) as code;
  if cardinality(selected) <> cardinality(service_codes) then
    raise exception 'Choose each service once.' using errcode = '22023';
  end if;
  select b.* into booking from public.herco_bookings b where b.id = booking_id for update;
  if not found then raise exception 'Booking not found.' using errcode = 'P0002'; end if;
  editable := herco_private.may_edit_booked_services(booking);
  select c.* into previous from herco_private.booking_service_changes c where c.booking_id = booking.id
    and c.actor_id = auth.uid() and c.request_id = herco_save_booked_services.request_id;
  if found then
    if selected is distinct from previous.service_codes or expected_revision <> previous.revision - 1 then
      raise exception 'This request ID belongs to another service selection.' using errcode = '22023';
    end if;
    return public.herco_booked_services(booking.id);
  end if;
  if not editable or booking.service_revision <> expected_revision then
    raise exception 'The booking changed or is no longer editable. Reload before retrying.' using errcode = '40001';
  end if;

  old_lines := coalesce(booking.current_services, booking.original_services);
  select jsonb_agg(line.snapshot order by choice.code),
    sum((line.snapshot->>'price_centavos')::bigint)
  into new_lines, total
  from unnest(selected) choice(code)
  cross join lateral (
    select item as snapshot from jsonb_array_elements(old_lines) item where item->>'code' = choice.code
    union all
    select jsonb_strip_nulls(jsonb_build_object('code', c.code, 'label', c.label,
      'price_centavos', c.price_centavos, 'promotion', c.promotion,
      'max_centavos', c.max_centavos, 'quote_required', case when c.quote_required then true end)) from public.herco_catalog() c
    where c.code = choice.code and extract(dow from booking.visit_date)::smallint = any(c.appointment_days)
      and not exists (select 1 from jsonb_array_elements(old_lines) item where item->>'code' = choice.code)
  ) line;
  if new_lines is null or jsonb_array_length(new_lines) <> cardinality(selected) or total is null then
    raise exception 'A selected service is unavailable on the booked date.' using errcode = '22023';
  end if;
  if new_lines = old_lines then return public.herco_booked_services(booking.id); end if;
  update public.herco_bookings b set current_services = new_lines,
    current_total_centavos = total, service_revision = b.service_revision + 1 where b.id = booking.id;
  insert into herco_private.booking_service_changes (
    booking_id, actor_id, request_id, revision, service_codes, before_services, after_services, recorded_at
  ) values (booking.id, auth.uid(), request_id, expected_revision + 1, selected, old_lines, new_lines, changed_at);
  insert into public.herco_booking_events (booking_id, actor_id, kind, to_status)
    values (booking.id, auth.uid(), 'booking_services_updated', booking.status);
  return public.herco_booked_services(booking.id);
end
$$;

revoke all on function herco_private.may_edit_booked_services(public.herco_bookings),
  public.herco_booked_services(uuid), public.herco_save_booked_services(uuid, uuid, integer, text[])
  from public, anon, authenticated;
grant execute on function public.herco_booked_services(uuid), public.herco_save_booked_services(uuid, uuid, integer, text[])
  to authenticated;

create or replace function public.herco_staff_booking_day(visit_date date)
returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  grants text[] := herco_private.staff_booking_grants();
  shop_now timestamp := statement_timestamp() at time zone 'Asia/Manila';
  override_open boolean;
  items jsonb;
  slots jsonb;
begin
  if visit_date is null or not isfinite(visit_date) then
    raise exception 'Choose a valid calendar date.' using errcode = '22023';
  end if;

  select o.is_open into override_open from herco_private.date_overrides as o
    where o.visit_date = herco_staff_booking_day.visit_date;
  select jsonb_agg(jsonb_build_object(
    'id', b.id,
    'visit_hour', b.visit_hour,
    'bike', b.bike,
    'customer_name', b.customer_contact->>'name',
    'customer_phone', b.customer_contact->>'phone',
    'status', b.status,
    'services', (select jsonb_agg(s->>'label') from jsonb_array_elements(coalesce(b.current_services, b.original_services)) as s),
    'approval_note', n.body
  ) order by b.visit_hour, b.id)
  into items
  from public.herco_bookings b
  left join herco_private.booking_approval_notes n on n.booking_id = b.id
  where b.visit_date = herco_staff_booking_day.visit_date and b.status <> 'cancelled';

  select jsonb_agg(jsonb_build_object(
    'hour', hour,
    'status', herco_private.slot_status(visit_date, hour::smallint, shop_now),
    'blocked', exists (
      select 1 from herco_private.slot_blocks s
      where s.visit_date = herco_staff_booking_day.visit_date and s.visit_hour = hour
    )
  ) order by hour)
  into slots
  from generate_series(9, 16) as hour;

  return jsonb_build_object(
    'bookings', coalesce(items, '[]'::jsonb),
    'slots', slots,
    'override', override_open,
    'can_confirm', 'confirmBooking' = any (grants),
    'can_edit_services', 'editServices' = any (grants),
    'can_manage_schedule', 'manageSchedule' = any (grants),
    'can_view_points', exists (
      select 1 from herco_private.staff_memberships m
      where m.user_id = auth.uid() and m.enabled and 'HERCO Points' = any (m.page_grants)
    ),
    'past_date', visit_date < shop_now::date
  );
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
      if request.target_date > shop_now::date + 20
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

create or replace function public.herco_complete_booking(booking uuid, price_centavos bigint, photos text[], completion_note text)
returns timestamptz language plpgsql volatile security definer set search_path = '' as $$
declare current_booking public.herco_bookings;
  existing herco_private.booking_completion;
  prefix text := booking::text || '/' || auth.uid()::text || '/';
  normalized_note text := btrim(coalesce(completion_note, ''));
  completed timestamptz;
begin
  perform herco_private.require_completion_staff();
  if booking is null or price_centavos is null or price_centavos not between 0 and 99999999999
    or photos is null or cardinality(photos) not between 1 and 3 or char_length(normalized_note) > 500
    or (select count(distinct path) from unnest(photos) path) <> cardinality(photos) then
    raise exception 'Enter a final price and attach one to three photos.' using errcode = '22023';
  end if;
  select b.* into current_booking from public.herco_bookings b where b.id = booking for update;
  if not found then raise exception 'Booking not found.' using errcode = '22023'; end if;
  select c.* into existing from herco_private.booking_completion c where c.booking_id = booking;
  if found then
    if existing.actor_id = auth.uid() and existing.final_price_centavos = price_centavos
      and existing.photo_paths = photos and existing.note = normalized_note then return existing.completed_at; end if;
    raise exception 'This booking was already completed.' using errcode = '23514';
  end if;
  if current_booking.status <> 'confirmed' then
    raise exception 'Only a confirmed booking can be completed.' using errcode = '23514';
  end if;
  if coalesce(current_booking.current_services, current_booking.original_services) = '[]'::jsonb or exists (
    select 1 from jsonb_array_elements(coalesce(current_booking.current_services, current_booking.original_services)) s
    where jsonb_typeof(s->'price_centavos') is distinct from 'number'
      or s->>'quote_required' = 'true' or s->>'max_centavos' is not null
  ) then raise exception 'Set exact prices for all services before completing.' using errcode = '23514'; end if;
  if exists (
    select 1 from unnest(photos) path
    where not starts_with(path, prefix)
      or substring(path from length(prefix) + 1) !~ '^[0-9a-f-]{36}\.(jpg|png|webp)$'
      or not exists (select 1 from storage.objects o where o.bucket_id = 'herco-completion' and o.name = path)
  ) then raise exception 'Upload valid photos for this booking.' using errcode = '22023'; end if;

  insert into herco_private.booking_completion(booking_id, actor_id, final_price_centavos, photo_paths, note)
    values (booking, auth.uid(), price_centavos, photos, normalized_note) returning completed_at into completed;
  update public.herco_bookings set status = 'done' where id = booking;
  insert into public.herco_booking_events(booking_id, actor_id, kind, to_status)
    values (booking, auth.uid(), 'completed', 'done');
  return completed;
end;
$$;

commit;
