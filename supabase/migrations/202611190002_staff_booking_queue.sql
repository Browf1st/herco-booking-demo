begin;

create table herco_private.booking_approval_notes (
  booking_id uuid primary key references public.herco_bookings(id),
  body text not null check (char_length(body) between 1 and 500)
);
alter table herco_private.booking_approval_notes enable row level security;
revoke all on herco_private.booking_approval_notes from public, anon, authenticated;

create function herco_private.staff_booking_grants()
returns text[]
language plpgsql volatile set search_path = '' as $$
declare
  grants text[];
begin
  if auth.uid() is null or (auth.jwt()->>'aal') is distinct from 'aal2' then
    raise exception 'Verify your staff session first.' using errcode = '42501';
  end if;
  select m.action_grants into grants
  from herco_private.staff_memberships as m
  where m.user_id = auth.uid() and m.enabled and 'Bookings' = any (m.page_grants)
  for share;
  if not found then
    raise exception 'You do not have access to the booking queue.' using errcode = '42501';
  end if;
  return grants;
end
$$;

create function public.herco_staff_booking_day(visit_date date)
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
    'services', (select jsonb_agg(s->>'label') from jsonb_array_elements(b.original_services) as s),
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
    'can_manage_schedule', 'manageSchedule' = any (grants),
    'can_view_points', exists (
      select 1 from herco_private.staff_memberships m
      where m.user_id = auth.uid() and m.enabled and 'HERCO Points' = any (m.page_grants)
    ),
    'past_date', visit_date < shop_now::date
  );
end
$$;

create function public.herco_confirm_booking(booking_id uuid, approval_note text default '')
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
  values (event_id, 'booking_confirmed', booking.customer_contact->>'email', jsonb_build_object(
    'booking_id', booking.id, 'visit_date', booking.visit_date, 'visit_hour', booking.visit_hour));
end
$$;

revoke all on function herco_private.staff_booking_grants(),
  public.herco_staff_booking_day(date), public.herco_confirm_booking(uuid, text) from public, anon, authenticated;
grant execute on function public.herco_staff_booking_day(date), public.herco_confirm_booking(uuid, text) to authenticated;

commit;
