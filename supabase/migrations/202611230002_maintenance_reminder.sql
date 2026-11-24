-- F-017: 6-month maintenance reminder email. Additive.
-- When a booking becomes Done, one outbox job 'maintenance_reminder' is queued for 9:00 AM Philippine time
-- on the date 6 months later (month-end clamped). It is cancelled if the booking leaves Done. The email
-- Worker re-checks everything at send time (herco_check_maintenance_reminder_outbox).
-- Existing Done bookings are not back-filled. Run on local or staging first; applying to hosted Supabase
-- is a separate, approved release step.
begin;

------------------------------------------------------------------ opt-outs
create table herco_private.reminder_opt_outs (
  customer_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table herco_private.reminder_opt_outs enable row level security;
revoke all on herco_private.reminder_opt_outs from public, anon, authenticated;

------------------------------------------------------------------ one reminder per booking
create unique index herco_maintenance_reminder_booking
  on herco_private.notification_outbox ((payload->>'booking_id'))
  where template = 'maintenance_reminder';

------------------------------------------------------------------ queue on Done
-- The Done event row (kind 'completed') is written by herco_complete_booking after the booking is updated.
-- Other events on a Done booking (price corrections, service edits, change requests) never touch the job.
-- Done twice (undo, then Done again) re-uses the same job while it is still unsent.
create function herco_private.enqueue_maintenance_reminder()
returns trigger language plpgsql volatile security definer set search_path = '' as $$
declare
  booked public.herco_bookings;
  to_email text;
  due timestamptz;
begin
  select b.* into booked from public.herco_bookings as b where b.id = new.booking_id;
  to_email := nullif(btrim(booked.customer_contact->>'email'), '');
  if not found or to_email is null then return new; end if;

  due := (((new.created_at at time zone 'Asia/Manila')::date + interval '6 months')::date + time '09:00')
    at time zone 'Asia/Manila';

  insert into herco_private.notification_outbox as o (event_id, template, recipient, payload, available_at)
  values (new.id, 'maintenance_reminder', to_email,
    jsonb_build_object('booking_id', booked.id, 'customer_id', booked.customer_id), due)
  on conflict ((payload->>'booking_id')) where template = 'maintenance_reminder' do update
    set event_id = excluded.event_id, recipient = excluded.recipient, payload = excluded.payload,
      available_at = excluded.available_at, skipped_at = null, last_outcome = null, attempts = 0
    where o.sent_at is null and o.failed_at is null and o.review_at is null and o.lease_until is null;
  return new;
end;
$$;

create trigger herco_maintenance_reminder_queue
after insert on public.herco_booking_events
for each row when (new.kind = 'completed' and new.to_status = 'done')
execute function herco_private.enqueue_maintenance_reminder();

------------------------------------------------------------------ cancel when the booking leaves Done
create function herco_private.cancel_maintenance_reminder()
returns trigger language plpgsql volatile security definer set search_path = '' as $$
begin
  update herco_private.notification_outbox as o
  set skipped_at = statement_timestamp(), lease_until = null, lease_token = null, last_outcome = 'stale'
  where o.template = 'maintenance_reminder' and o.payload->>'booking_id' = new.id::text
    and o.sent_at is null and o.failed_at is null and o.skipped_at is null and o.review_at is null;
  return new;
end;
$$;

create trigger herco_maintenance_reminder_cancel
after update of status on public.herco_bookings
for each row when (old.status = 'done' and new.status <> 'done')
execute function herco_private.cancel_maintenance_reminder();

------------------------------------------------------------------ claim: maintenance jobs only for a configured Worker
-- Same as 0008 plus include_maintenance (default false), so a Worker without the token secret and site
-- address never claims these jobs, and an older Worker never claims a template it cannot render.
drop function public.herco_claim_notification_outbox(integer, boolean);
create function public.herco_claim_notification_outbox(
  batch_size integer default 5, include_reminders boolean default false, include_maintenance boolean default false
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
        and (include_maintenance is true or o.template <> 'maintenance_reminder')
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

------------------------------------------------------------------ send-time re-check
-- Returns null when the claim is not valid, {"status":"stale"} after skipping the job, or
-- {"status":"ready", ...} with only what the email shows: first name, service names, default hours.
create function public.herco_check_maintenance_reminder_outbox(job_id bigint, claim_token uuid)
returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  claimed herco_private.notification_outbox;
  checked_at timestamptz := statement_timestamp();
  shop_now timestamp := statement_timestamp() at time zone 'Asia/Manila';
  booked public.herco_bookings;
  hours herco_private.schedule_settings;
  names jsonb;
begin
  select o.* into claimed
  from herco_private.notification_outbox as o
  where o.id = job_id and o.lease_token = claim_token and o.template = 'maintenance_reminder'
    and o.lease_until > checked_at and o.sent_at is null and o.failed_at is null
    and o.skipped_at is null and o.review_at is null
  for update;
  if not found then return null; end if;

  select b.* into booked from public.herco_bookings as b
  where b.id = (claimed.payload->>'booking_id')::uuid;

  if found and booked.status = 'done'
    and booked.customer_id = (claimed.payload->>'customer_id')::uuid
    and lower(btrim(booked.customer_contact->>'email')) = lower(btrim(claimed.recipient))
    and exists (select 1 from auth.users as u where u.id = booked.customer_id)
    and not exists (select 1 from herco_private.reminder_opt_outs as x where x.customer_id = booked.customer_id)
    and not exists (
      select 1 from public.herco_bookings as f
      where f.customer_id = booked.customer_id and f.status in ('pending', 'confirmed')
        and f.visit_date + make_time(coalesce(f.visit_hour, 23), 0, 0) > shop_now)
  then
    select s.* into hours from herco_private.schedule_settings as s;
    if not found then raise exception 'Opening hours are not set up.' using errcode = '55000'; end if;
    select coalesce(jsonb_agg(e.s->>'label' order by e.n) filter (where nullif(btrim(e.s->>'label'), '') is not null), '[]'::jsonb)
    into names
    from jsonb_array_elements(coalesce(booked.current_services, booked.original_services)) with ordinality as e(s, n);
    return jsonb_build_object('status', 'ready',
      'firstName', split_part(btrim(coalesce(booked.customer_contact->>'name', '')), ' ', 1),
      'services', names,
      'openHour', hours.open_hour, 'closeHour', hours.close_hour, 'openWeekdays', to_jsonb(hours.open_weekdays));
  end if;

  update herco_private.notification_outbox as o
  set lease_until = null, lease_token = null, skipped_at = checked_at, last_outcome = 'stale'
  where o.id = claimed.id;
  return jsonb_build_object('status', 'stale');
end;
$$;

------------------------------------------------------------------ opt-out functions
-- Signed-in customer: own setting only (auth.uid()).
create function public.herco_get_maintenance_reminders()
returns boolean
language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null then
    raise exception 'Sign in to change reminder settings.' using errcode = '42501';
  end if;
  return not exists (select 1 from herco_private.reminder_opt_outs as x where x.customer_id = auth.uid());
end;
$$;

create function public.herco_set_maintenance_reminders(p_enabled boolean)
returns boolean
language plpgsql volatile security definer set search_path = '' as $$
begin
  if auth.uid() is null then
    raise exception 'Sign in to change reminder settings.' using errcode = '42501';
  end if;
  if p_enabled is null then
    raise exception 'Choose on or off.' using errcode = '22023';
  end if;
  if p_enabled then
    delete from herco_private.reminder_opt_outs as x where x.customer_id = auth.uid();
  else
    insert into herco_private.reminder_opt_outs (customer_id) values (auth.uid()) on conflict do nothing;
  end if;
  return p_enabled;
end;
$$;

-- Unsubscribe link: the site server checks the signed token, then calls this with its secret key.
-- Not callable by browsers. Repeating it, or an unknown customer, changes nothing and raises no error.
create function public.herco_unsubscribe_maintenance_reminders(p_customer uuid)
returns void
language plpgsql volatile security definer set search_path = '' as $$
begin
  if p_customer is null then
    raise exception 'Customer is required.' using errcode = '22023';
  end if;
  insert into herco_private.reminder_opt_outs (customer_id)
  select u.id from auth.users as u where u.id = p_customer
  on conflict do nothing;
end;
$$;

revoke all on function herco_private.enqueue_maintenance_reminder(), herco_private.cancel_maintenance_reminder(),
  public.herco_claim_notification_outbox(integer, boolean, boolean),
  public.herco_check_maintenance_reminder_outbox(bigint, uuid),
  public.herco_get_maintenance_reminders(), public.herco_set_maintenance_reminders(boolean),
  public.herco_unsubscribe_maintenance_reminders(uuid)
  from public, anon, authenticated;
grant execute on function public.herco_claim_notification_outbox(integer, boolean, boolean),
  public.herco_check_maintenance_reminder_outbox(bigint, uuid),
  public.herco_unsubscribe_maintenance_reminders(uuid)
  to service_role;
grant execute on function public.herco_get_maintenance_reminders(), public.herco_set_maintenance_reminders(boolean)
  to authenticated;

commit;
