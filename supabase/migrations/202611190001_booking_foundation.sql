-- Initial single-shop booking foundation. Apply to development or staging first.
begin;

create schema herco_private;
revoke all on schema herco_private from public, anon, authenticated;

create table herco_private.staff_memberships (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('staff', 'admin', 'restricted_admin', 'owner', 'superadmin')),
  enabled boolean not null default true,
  page_grants text[] not null default '{}',
  action_grants text[] not null default '{}'
);

create table herco_private.services (
  code text primary key check (code ~ '^[a-z0-9][a-z0-9-]{0,63}$'),
  label text not null check (char_length(label) between 1 and 120),
  price_centavos integer not null check (price_centavos >= 0),
  enabled boolean not null default false,
  appointment_days smallint[] not null default '{0,1,2,3,4,5,6}'
    check (cardinality(appointment_days) > 0 and appointment_days <@ '{0,1,2,3,4,5,6}'::smallint[])
);

-- These codes reserve the app's service identifiers. Configure real pricing before enabling them.
insert into herco_private.services (code, label, price_centavos, appointment_days)
values ('ceramic', 'Ceramic Coating', 0, '{0,1,2,3,4,5,6}'),
  ('wheel-colour', 'Powder Coating', 0, '{0,3,6}');

create table herco_private.date_overrides (
  visit_date date primary key,
  is_open boolean not null
);

create table herco_private.slot_blocks (
  visit_date date not null,
  visit_hour smallint not null check (visit_hour between 9 and 16),
  primary key (visit_date, visit_hour)
);

create table public.herco_bookings (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references auth.users(id),
  request_id uuid not null,
  request_payload jsonb not null,
  visit_date date not null,
  visit_hour smallint not null check (visit_hour between 9 and 16),
  bike text not null check (char_length(bike) between 1 and 120),
  customer_contact jsonb not null,
  status text not null default 'pending' check (status in ('pending', 'confirmed', 'done', 'cancelled')),
  original_services jsonb not null check (jsonb_typeof(original_services) = 'array'),
  original_total_centavos bigint not null check (original_total_centavos >= 0),
  created_at timestamptz not null default now(),
  unique (customer_id, request_id)
);

create unique index herco_active_booking_slot
  on public.herco_bookings (visit_date, visit_hour) where status <> 'cancelled';
create index herco_customer_booking_history on public.herco_bookings (customer_id, created_at desc, id desc);

create table public.herco_booking_events (
  id bigint generated always as identity primary key,
  booking_id uuid not null references public.herco_bookings(id),
  actor_id uuid not null references auth.users(id),
  kind text not null,
  to_status text not null check (to_status in ('pending', 'confirmed', 'done', 'cancelled')),
  created_at timestamptz not null default now()
);
create index herco_booking_event_history on public.herco_booking_events (booking_id, id);

create table herco_private.schedule_events (
  id bigint generated always as identity primary key,
  actor_id uuid not null references auth.users(id),
  visit_date date not null,
  visit_hour smallint,
  change text not null,
  created_at timestamptz not null default now()
);

create table herco_private.notification_outbox (
  id bigint generated always as identity primary key,
  event_id bigint not null references public.herco_booking_events(id),
  template text not null,
  recipient text not null,
  payload jsonb not null,
  attempts integer not null default 0 check (attempts >= 0),
  available_at timestamptz not null default now(),
  lease_until timestamptz,
  sent_at timestamptz,
  failed_at timestamptz,
  provider_message_id text,
  unique (event_id, template)
);

revoke all on all tables in schema herco_private from public, anon, authenticated;
alter table herco_private.staff_memberships enable row level security;
alter table herco_private.services enable row level security;
alter table herco_private.date_overrides enable row level security;
alter table herco_private.slot_blocks enable row level security;
alter table herco_private.notification_outbox enable row level security;
alter table herco_private.schedule_events enable row level security;

alter table public.herco_bookings enable row level security;
alter table public.herco_booking_events enable row level security;
revoke all on public.herco_bookings, public.herco_booking_events from public, anon, authenticated;
revoke all on sequence public.herco_booking_events_id_seq from public, anon, authenticated;
grant select on public.herco_bookings, public.herco_booking_events to authenticated;

create policy herco_customer_bookings on public.herco_bookings for select to authenticated
  using (customer_id = (select auth.uid()));
create policy herco_customer_events on public.herco_booking_events for select to authenticated
  using (exists (
    select 1 from public.herco_bookings as booking
    where booking.id = booking_id and booking.customer_id = (select auth.uid())
  ));

create function herco_private.slot_status(day date, hour smallint, shop_now timestamp)
returns text language sql stable set search_path = '' as $$
  select case
    when day + make_time(hour, 0, 0) <= shop_now then 'past'
    when exists (
      select 1 from public.herco_bookings as b
      where b.visit_date = day and b.visit_hour = hour and b.status <> 'cancelled'
    ) then 'booked'
    when not coalesce(
      (select o.is_open from herco_private.date_overrides as o where o.visit_date = day),
      extract(dow from day) in (0, 3, 4, 5, 6)
    ) then 'closed'
    when exists (
      select 1 from herco_private.slot_blocks as s where s.visit_date = day and s.visit_hour = hour
    ) then 'blocked'
    else 'open'
  end
$$;

create function public.herco_availability(from_date date, to_date date)
returns table (visit_date date, visit_hour smallint, status text)
language plpgsql stable security definer set search_path = '' as $$
declare
  shop_now timestamp := statement_timestamp() at time zone 'Asia/Manila';
begin
  if from_date is null or to_date is null or from_date < shop_now::date
    or to_date < from_date or to_date > shop_now::date + 20 then
    raise exception 'Choose dates within the next 21 days.' using errcode = '22023';
  end if;

  return query
    select from_date + day_offset, hour::smallint,
      herco_private.slot_status(from_date + day_offset, hour::smallint, shop_now)
    from generate_series(0, to_date - from_date) as day_offset
    cross join generate_series(9, 16) as hour
    order by day_offset, hour;
end
$$;

create function public.herco_catalog()
returns table (code text, label text, price_centavos integer, appointment_days smallint[])
language sql stable security definer set search_path = '' as $$
  select s.code, s.label, s.price_centavos, s.appointment_days
  from herco_private.services as s where s.enabled order by s.label, s.code
$$;

create function public.herco_create_booking(
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
language plpgsql volatile security definer set search_path = '' as $$
declare
  actor uuid := auth.uid();
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
  if actor is null then
    raise exception 'Sign in before booking.' using errcode = '42501';
  end if;

  select u.email into customer_email from auth.users as u
    where u.id = actor and u.email_confirmed_at is not null;
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

  -- Serialize identical request IDs before competing for a date.
  perform pg_advisory_xact_lock(72001, hashtext(actor::text || ':' || request_id::text));
  select b.* into booking from public.herco_bookings as b
    where b.customer_id = actor and b.request_id = herco_create_booking.request_id;
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
  values (actor, request_id, requested, visit_date, visit_hour, btrim(bike), contact, services, total)
  returning * into booking;

  insert into public.herco_booking_events (booking_id, actor_id, kind, to_status)
  values (booking.id, actor, 'booking_submitted', 'pending')
  returning id into booking_event_id;

  insert into herco_private.notification_outbox (event_id, template, recipient, payload)
  values (booking_event_id, 'booking_submitted', customer_email, jsonb_build_object(
    'booking_id', booking.id, 'visit_date', visit_date, 'visit_hour', visit_hour));
  return booking;
end
$$;

create function public.herco_set_availability(visit_date date, change text, visit_hour smallint default null)
returns void
language plpgsql volatile security definer set search_path = '' as $$
declare
  actor uuid := auth.uid();
  member herco_private.staff_memberships;
  shop_now timestamp;
begin
  if actor is null or (auth.jwt()->>'aal') is distinct from 'aal2' then
    raise exception 'Verify your staff session before changing availability.' using errcode = '42501';
  end if;

  select m.* into member from herco_private.staff_memberships as m
    where m.user_id = actor and m.enabled for share;
  if not found or ('Bookings' = any(member.page_grants) and 'manageSchedule' = any(member.action_grants)) is not true then
    raise exception 'You do not have permission to manage availability.' using errcode = '42501';
  end if;

  if visit_date is null or not isfinite(visit_date) or change is null
    or change not in ('open_date', 'close_date', 'restore_date', 'block_slot', 'unblock_slot')
    or (change in ('block_slot', 'unblock_slot') and (visit_hour is null or visit_hour not between 9 and 16))
    or (change in ('open_date', 'close_date', 'restore_date') and visit_hour is not null) then
    raise exception 'Choose a valid date and availability action.' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(72002, visit_date - date '2000-01-01');
  shop_now := clock_timestamp() at time zone 'Asia/Manila';
  if visit_date < shop_now::date
    or (change = 'block_slot' and visit_date + make_time(visit_hour, 0, 0) <= shop_now) then
    raise exception 'Choose a future appointment time.' using errcode = '22023';
  end if;

  case change
    when 'restore_date' then
      delete from herco_private.date_overrides as o where o.visit_date = herco_set_availability.visit_date;
    when 'block_slot' then
      insert into herco_private.slot_blocks values (visit_date, visit_hour) on conflict do nothing;
    when 'unblock_slot' then
      delete from herco_private.slot_blocks as s
        where s.visit_date = herco_set_availability.visit_date and s.visit_hour = herco_set_availability.visit_hour;
    else
      insert into herco_private.date_overrides as o values (visit_date, change = 'open_date')
      on conflict on constraint date_overrides_pkey do update set is_open = excluded.is_open
      where o.is_open is distinct from excluded.is_open;
  end case;
  if found then
    insert into herco_private.schedule_events (actor_id, visit_date, visit_hour, change)
    values (actor, visit_date, visit_hour, change);
  end if;
end
$$;

revoke all on function public.herco_set_availability(date, text, smallint) from public, anon, authenticated;
grant execute on function public.herco_set_availability(date, text, smallint) to authenticated;

revoke all on function herco_private.slot_status(date, smallint, timestamp) from public, anon, authenticated;
revoke all on function public.herco_availability(date, date), public.herco_catalog(),
  public.herco_create_booking(uuid, date, smallint, text[], text, text, text, text)
  from public, anon, authenticated;
grant execute on function public.herco_availability(date, date), public.herco_catalog() to anon, authenticated;
grant execute on function public.herco_create_booking(uuid, date, smallint, text[], text, text, text, text)
  to authenticated;

commit;
