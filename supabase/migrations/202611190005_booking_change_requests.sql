begin;

create table herco_private.booking_change_requests (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.herco_bookings(id),
  customer_id uuid not null references auth.users(id),
  submission_id uuid not null,
  kind text not null check (kind in ('cancel', 'reschedule')),
  reason text not null check (char_length(reason) <= 500),
  original_date date not null,
  original_hour smallint not null,
  target_date date,
  target_hour smallint,
  state text not null default 'pending' check (state in ('pending', 'approved', 'declined')),
  created_at timestamptz not null default now(),
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  unique (customer_id, submission_id),
  check ((kind = 'cancel' and target_date is null and target_hour is null) or
    (kind = 'reschedule' and target_date is not null and target_hour is not null and target_hour between 9 and 16))
);
create unique index herco_one_pending_change on herco_private.booking_change_requests (booking_id) where state = 'pending';
create index herco_pending_change_queue on herco_private.booking_change_requests (created_at, id) where state = 'pending';
create index herco_change_history on herco_private.booking_change_requests (booking_id, created_at desc);
alter table herco_private.booking_change_requests enable row level security;
revoke all on herco_private.booking_change_requests from public, anon, authenticated;

create function public.herco_request_booking_change(
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

create function public.herco_customer_booking_changes(booking_ids uuid[])
returns table (id uuid, booking_id uuid, kind text, reason text, state text,
  original_date date, original_hour smallint, target_date date, target_hour smallint,
  created_at timestamptz, reviewed_at timestamptz)
language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'Sign in to see your change requests.' using errcode = '42501'; end if;
  if coalesce(cardinality(booking_ids), 0) not between 1 and 20 then
    raise exception 'Choose up to 20 bookings.' using errcode = '22023';
  end if;
  return query
    select r.id, r.booking_id, r.kind, r.reason, r.state, r.original_date, r.original_hour,
      r.target_date, r.target_hour, r.created_at, r.reviewed_at
    from unnest(booking_ids) as booking
    cross join lateral (
      select q.* from herco_private.booking_change_requests q
      where q.booking_id = booking and q.customer_id = auth.uid()
      order by q.created_at desc, q.id desc limit 5
    ) r;
end
$$;

create function herco_private.staff_change_grants()
returns text[]
language plpgsql volatile set search_path = '' as $$
declare grants text[];
begin
  if auth.uid() is null or (auth.jwt()->>'aal') is distinct from 'aal2' then
    raise exception 'Verify your staff session first.' using errcode = '42501';
  end if;
  select m.action_grants into grants from herco_private.staff_memberships m
    where m.user_id = auth.uid() and m.enabled and 'Change requests' = any (m.page_grants) for share;
  if not found then raise exception 'You do not have access to change requests.' using errcode = '42501'; end if;
  return grants;
end
$$;

create function public.herco_staff_booking_changes(skip integer default 0)
returns table (id uuid, booking_id uuid, kind text, reason text, customer_name text,
  original_date date, original_hour smallint, target_date date, target_hour smallint, created_at timestamptz,
  can_review boolean)
language plpgsql volatile security definer set search_path = '' as $$
declare grants text[] := herco_private.staff_change_grants();
begin
  if skip is null or skip not between 0 and 5000 then
    raise exception 'Choose a valid page.' using errcode = '22023';
  end if;
  return query
    select r.id, r.booking_id, r.kind, r.reason, b.customer_contact->>'name',
      r.original_date, r.original_hour, r.target_date, r.target_hour, r.created_at,
      case when r.kind = 'cancel' then 'reviewCancellation' = any(grants)
        else 'reviewReschedule' = any(grants) end
    from herco_private.booking_change_requests r join public.herco_bookings b on b.id = r.booking_id
    where r.state = 'pending' order by r.created_at, r.id limit 21 offset skip;
end
$$;

create function public.herco_review_booking_change(request_id uuid, decision text)
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
          select 1 from jsonb_array_elements(booking.original_services) as service
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

revoke all on function herco_private.staff_change_grants(),
  public.herco_request_booking_change(uuid, uuid, text, text, date, smallint),
  public.herco_customer_booking_changes(uuid[]), public.herco_staff_booking_changes(integer),
  public.herco_review_booking_change(uuid, text) from public, anon, authenticated;
grant execute on function public.herco_request_booking_change(uuid, uuid, text, text, date, smallint),
  public.herco_customer_booking_changes(uuid[]), public.herco_staff_booking_changes(integer),
  public.herco_review_booking_change(uuid, text) to authenticated;

commit;
