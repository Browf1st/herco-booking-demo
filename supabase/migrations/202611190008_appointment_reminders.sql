-- Local appointment times are stored as a Philippine date and hour.
create function herco_private.herco_appointment_timestamp(visit_date date, visit_hour smallint)
returns timestamptz
language sql immutable set search_path = '' as $$
  select (visit_date + make_interval(hours => visit_hour)) at time zone 'Asia/Manila';
$$;

create function herco_private.herco_latest_appointment_event(booking_id uuid)
returns bigint
language sql stable set search_path = '' as $$
  select e.id
  from public.herco_booking_events as e
  where e.booking_id = $1 and e.to_status = 'confirmed'
    and e.kind in ('booking_confirmed', 'booking_reschedule_approved')
  order by e.id desc
  limit 1;
$$;

revoke all on function herco_private.herco_appointment_timestamp(date, smallint),
  herco_private.herco_latest_appointment_event(uuid) from public, anon, authenticated;

create function public.herco_enqueue_appointment_reminders(lead_hours integer)
returns integer
language plpgsql volatile security definer set search_path = '' as $$
declare
  current_time_at timestamptz := statement_timestamp();
  window_end timestamptz;
  queued integer;
begin
  if lead_hours is null or lead_hours not between 1 and 168 then
    raise exception 'Appointment reminder lead time must be 1 to 168 hours.' using errcode = '22023';
  end if;

  window_end := current_time_at + make_interval(hours => lead_hours);
  insert into herco_private.notification_outbox (event_id, template, recipient, payload)
  select source.event_id, 'appointment_reminder', booking.customer_contact->>'email',
    jsonb_build_object('booking_id', booking.id, 'visit_date', booking.visit_date, 'visit_hour', booking.visit_hour)
  from public.herco_bookings as booking
  cross join lateral (select herco_private.herco_latest_appointment_event(booking.id) as event_id) as source
  where booking.status = 'confirmed'
    and booking.visit_date between (current_time_at at time zone 'Asia/Manila')::date
      and (window_end at time zone 'Asia/Manila')::date
    and herco_private.herco_appointment_timestamp(booking.visit_date, booking.visit_hour)
      > current_time_at
    and herco_private.herco_appointment_timestamp(booking.visit_date, booking.visit_hour)
      <= window_end
    and nullif(btrim(booking.customer_contact->>'email'), '') is not null
    and source.event_id is not null
    and not exists (
      select 1 from herco_private.notification_outbox as o
      where o.event_id = source.event_id and o.template = 'appointment_reminder'
    )
  order by booking.visit_date, booking.visit_hour, booking.id
  limit 20
  for update of booking skip locked
  on conflict (event_id, template) do nothing;
  get diagnostics queued = row_count;
  return queued;
end;
$$;

-- Existing workers calling with only batch_size continue to receive transactional jobs.
drop function public.herco_claim_notification_outbox(integer);
create function public.herco_claim_notification_outbox(
  batch_size integer default 5, include_reminders boolean default false
)
returns table (id text, lease_token uuid, template text, recipient text, payload jsonb)
language plpgsql volatile security definer set search_path = '' as $$
declare
  claimed_at timestamptz := statement_timestamp();
  claim_token uuid := gen_random_uuid();
begin
  if batch_size is null or batch_size not between 1 and 5 then
    raise exception 'Choose a batch size from 1 to 5.' using errcode = '22023';
  end if;

  with expired as (
    select o.id
    from herco_private.notification_outbox as o
    where o.lease_until <= claimed_at
      and o.sent_at is null and o.failed_at is null
      and o.skipped_at is null and o.review_at is null
    order by o.lease_until, o.id
    limit batch_size
    for update skip locked
  )
  update herco_private.notification_outbox as o
  set review_at = claimed_at, last_outcome = 'expired-lease',
    lease_until = null, lease_token = null
  from expired
  where o.id = expired.id;

  return query
    with ready as (
      select o.id
      from herco_private.notification_outbox as o
      where o.available_at <= claimed_at and o.lease_until is null
        and o.sent_at is null and o.failed_at is null
        and o.skipped_at is null and o.review_at is null
        and o.attempts < 5
        and (include_reminders is true or o.template <> 'appointment_reminder')
      order by o.available_at, o.id
      limit batch_size
      for update skip locked
    )
    update herco_private.notification_outbox as o
    set lease_until = claimed_at + interval '2 minutes',
      lease_token = claim_token, attempts = o.attempts + 1
    from ready
    where o.id = ready.id
    returning o.id::text, o.lease_token, o.template, o.recipient, o.payload;
end;
$$;

-- Recheck immediately before contacting Brevo. An obsolete reminder becomes terminal.
create function public.herco_check_reminder_outbox(job_id bigint, claim_token uuid)
returns text
language plpgsql volatile security definer set search_path = '' as $$
declare
  claimed herco_private.notification_outbox;
  current_time_at timestamptz := statement_timestamp();
begin
  select o.* into claimed
  from herco_private.notification_outbox as o
  where o.id = job_id and o.lease_token = claim_token and o.template = 'appointment_reminder'
    and o.lease_until > current_time_at and o.sent_at is null and o.failed_at is null
    and o.skipped_at is null and o.review_at is null
  for update;
  if not found then return null; end if;

  if exists (
    select 1
    from public.herco_booking_events as e
    join public.herco_bookings as b on b.id = e.booking_id
    where e.id = claimed.event_id and b.status = 'confirmed'
      and to_jsonb(b.visit_date) = claimed.payload->'visit_date'
      and to_jsonb(b.visit_hour) = claimed.payload->'visit_hour'
      and b.customer_contact->>'email' = claimed.recipient
      and herco_private.herco_latest_appointment_event(b.id) = e.id
      and herco_private.herco_appointment_timestamp(b.visit_date, b.visit_hour) > current_time_at
  ) then return 'ready'; end if;

  update herco_private.notification_outbox as o
  set lease_until = null, lease_token = null, skipped_at = current_time_at, last_outcome = 'stale'
  where o.id = claimed.id;
  return 'stale';
end;
$$;

revoke all on function public.herco_enqueue_appointment_reminders(integer),
  public.herco_claim_notification_outbox(integer, boolean),
  public.herco_check_reminder_outbox(bigint, uuid) from public, anon, authenticated;
grant execute on function public.herco_enqueue_appointment_reminders(integer),
  public.herco_claim_notification_outbox(integer, boolean),
  public.herco_check_reminder_outbox(bigint, uuid) to service_role;
