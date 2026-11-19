begin;

create table herco_private.staff_booking_changes (
  actor_id uuid not null references auth.users(id),
  request_id uuid not null,
  booking_id uuid not null references public.herco_bookings(id),
  event_id bigint not null unique references public.herco_booking_events(id),
  details jsonb not null,
  primary key (actor_id, request_id)
);
alter table herco_private.staff_booking_changes enable row level security;
revoke all on herco_private.staff_booking_changes from public, anon, authenticated;

create function public.herco_staff_change_booking(
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
    or original_date is null or not isfinite(original_date) or original_hour is null or original_hour not between 9 and 16
    or char_length(note) > 500
    or (kind = 'cancel' and (target_date is not null or target_hour is not null))
    or (kind = 'reschedule' and (target_date is null or not isfinite(target_date) or target_hour is null or target_hour not between 9 and 16
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
  if original_date + make_time(original_hour, 0, 0) <= shop_now then
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
    values (event_id, event_kind, booking.customer_contact->>'email', jsonb_build_object(
      'booking_id', booking.id, 'visit_date', booking.visit_date, 'visit_hour', booking.visit_hour));
end
$$;

create or replace function herco_private.herco_latest_appointment_event(booking_id uuid)
returns bigint
language sql stable set search_path = '' as $$
  select e.id
  from public.herco_booking_events as e
  where e.booking_id = $1 and e.to_status = 'confirmed'
    and e.kind in ('booking_confirmed', 'booking_reschedule_approved', 'booking_rescheduled_by_staff')
  order by e.id desc
  limit 1;
$$;

revoke all on function public.herco_staff_change_booking(uuid, uuid, text, date, smallint, text, date, smallint)
  from public, anon, authenticated;
grant execute on function public.herco_staff_change_booking(uuid, uuid, text, date, smallint, text, date, smallint)
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
    'approval_note', n.body,
    'request_pending', exists (select 1 from herco_private.booking_change_requests r
      where r.booking_id = b.id and r.state = 'pending')
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
    'can_cancel', 'cancelBooking' = any (grants),
    'can_reschedule', 'rescheduleBooking' = any (grants),
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

commit;
