begin;

create table herco_private.walk_in_forms (
  version text primary key check (char_length(version) between 1 and 60 and btrim(version) = version),
  title text not null check (char_length(btrim(title)) between 1 and 120),
  body text not null check (char_length(btrim(body)) between 1 and 16000),
  signature_method text not null check (signature_method = 'typed_name'),
  approved_by uuid not null,
  approved_at timestamptz not null,
  active boolean not null default false
);
create unique index herco_single_active_walk_in_form on herco_private.walk_in_forms (active) where active;

create function herco_private.keep_walk_in_form_version()
returns trigger language plpgsql set search_path = '' as $$
begin
  if (to_jsonb(new) - 'active') is distinct from (to_jsonb(old) - 'active') then
    raise exception 'Create a new version when the approved form changes.' using errcode = '22023';
  end if;
  return new;
end
$$;

create trigger herco_keep_walk_in_form_version
before update on herco_private.walk_in_forms
for each row execute function herco_private.keep_walk_in_form_version();

create table herco_private.walk_in_intakes (
  booking_id uuid not null references public.herco_bookings(id),
  form_version text not null references herco_private.walk_in_forms(version),
  requested_by uuid not null,
  requested_at timestamptz not null default clock_timestamp(),
  signer_user_id uuid,
  signer_name text,
  signed_at timestamptz,
  acknowledged boolean not null default false,
  primary key (booking_id, form_version),
  check (
    (signer_user_id is null and signer_name is null and signed_at is null and not acknowledged)
    or (signer_user_id is not null and signer_name is not null and signed_at is not null and acknowledged
      and char_length(btrim(signer_name)) between 1 and 120 and signed_at >= requested_at)
  )
);
create unique index herco_one_signed_intake_per_booking on herco_private.walk_in_intakes (booking_id) where signed_at is not null;

alter table herco_private.walk_in_forms enable row level security;
alter table herco_private.walk_in_intakes enable row level security;
revoke all on herco_private.walk_in_forms, herco_private.walk_in_intakes from public, anon, authenticated;

create function herco_private.walk_in_actor()
returns uuid
language plpgsql stable set search_path = '' as $$
declare
  actor uuid := auth.uid();
begin
  if actor is null or not exists (
    select 1 from auth.users u where u.id = actor and u.email_confirmed_at is not null
  ) then
    raise exception 'Sign in with a verified HERCO account.' using errcode = '42501';
  end if;
  return actor;
end
$$;

create function herco_private.can_request_walk_in_intake(lock_grant boolean)
returns boolean
language plpgsql volatile set search_path = '' as $$
begin
  if (auth.jwt()->>'aal') is distinct from 'aal2' then return false; end if;
  if lock_grant then
    perform 1 from herco_private.staff_memberships m
    where m.user_id = auth.uid() and m.enabled and 'Bookings' = any(m.page_grants)
      and 'createBooking' = any(m.action_grants) for share;
  else
    perform 1 from herco_private.staff_memberships m
    where m.user_id = auth.uid() and m.enabled and 'Bookings' = any(m.page_grants)
      and 'createBooking' = any(m.action_grants);
  end if;
  return found;
end
$$;

create function public.herco_walk_in_intake(p_booking_id uuid)
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
  customer := booking.customer_id = actor;

  select i.* into intake from herco_private.walk_in_intakes i
  where i.booking_id = booking.id and i.signed_at is not null;
  if found then
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

create function public.herco_request_walk_in_intake(p_booking_id uuid, p_form_version text)
returns void
language plpgsql volatile security definer set search_path = '' as $$
declare
  actor uuid := herco_private.walk_in_actor();
  booking public.herco_bookings;
begin
  if not herco_private.can_request_walk_in_intake(true) then
    raise exception 'Verify your staff session and check your intake permission.' using errcode = '42501';
  end if;
  select b.* into booking from public.herco_bookings b where b.id = p_booking_id for update;
  if not found then raise exception 'This booking could not be found.' using errcode = 'P0002'; end if;

  if exists (
    select 1 from herco_private.walk_in_intakes i
    where i.booking_id = booking.id and i.signed_at is not null
  ) then return; end if;
  if booking.status not in ('pending', 'confirmed') then
    raise exception 'This booking no longer accepts an intake form.' using errcode = '23P01';
  end if;
  if not exists (
    select 1 from auth.users u where u.id = booking.customer_id and u.email_confirmed_at is not null
  ) then
    raise exception 'The booking owner must have a verified account.' using errcode = '42501';
  end if;
  perform 1 from herco_private.walk_in_forms f where f.version = p_form_version and f.active for share;
  if not found then
    raise exception 'The approved form changed or is unavailable. Reload the intake.' using errcode = '23P01';
  end if;

  insert into herco_private.walk_in_intakes(booking_id, form_version, requested_by)
    values (booking.id, p_form_version, actor)
    on conflict (booking_id, form_version) do nothing;
  if found then
    insert into public.herco_booking_events(booking_id, actor_id, kind, to_status)
      values (booking.id, actor, 'walk_in_intake_requested', booking.status);
  end if;
end
$$;

create function public.herco_sign_walk_in_intake(p_booking_id uuid, p_form_version text, p_name text, p_acknowledged boolean)
returns void
language plpgsql volatile security definer set search_path = '' as $$
declare
  actor uuid := herco_private.walk_in_actor();
  booking public.herco_bookings;
  intake herco_private.walk_in_intakes;
  printed_name text := btrim(p_name);
begin
  if p_acknowledged is distinct from true or coalesce(char_length(printed_name), 0) not between 1 and 120 then
    raise exception 'Review the approved form and type your full name.' using errcode = '22023';
  end if;
  select b.* into booking from public.herco_bookings b
  where b.id = p_booking_id and b.customer_id = actor for update;
  if not found then raise exception 'This booking is unavailable to your account.' using errcode = 'P0002'; end if;
  if lower(printed_name) is distinct from lower(btrim(booking.customer_contact->>'name')) then
    raise exception 'Use the full name shown on your booking.' using errcode = '22023';
  end if;
  select i.* into intake from herco_private.walk_in_intakes i
  where i.booking_id = booking.id and i.form_version = p_form_version;
  if not found then
    raise exception 'The shop must request intake for this booking first.' using errcode = '23P01';
  end if;
  if intake.signed_at is not null then return; end if;
  if booking.status not in ('pending', 'confirmed') or exists (
    select 1 from herco_private.walk_in_intakes i where i.booking_id = booking.id and i.signed_at is not null
  ) then
    raise exception 'This booking no longer accepts an intake form.' using errcode = '23P01';
  end if;
  perform 1 from herco_private.walk_in_forms f
  where f.version = p_form_version and f.active and f.signature_method = 'typed_name' for share;
  if not found then
    raise exception 'The approved form changed or is unavailable. Reload the intake.' using errcode = '23P01';
  end if;

  update herco_private.walk_in_intakes
    set signer_user_id = actor, signer_name = printed_name, signed_at = clock_timestamp(), acknowledged = true
    where booking_id = booking.id and form_version = p_form_version;
  insert into public.herco_booking_events(booking_id, actor_id, kind, to_status)
    values (booking.id, actor, 'walk_in_intake_signed', booking.status);
end
$$;

revoke all on function herco_private.keep_walk_in_form_version(), herco_private.walk_in_actor(),
  herco_private.can_request_walk_in_intake(boolean) from public, anon, authenticated;
revoke all on function public.herco_walk_in_intake(uuid), public.herco_request_walk_in_intake(uuid, text),
  public.herco_sign_walk_in_intake(uuid, text, text, boolean) from public, anon, authenticated;
grant execute on function public.herco_walk_in_intake(uuid), public.herco_request_walk_in_intake(uuid, text),
  public.herco_sign_walk_in_intake(uuid, text, text, boolean) to authenticated;

commit;
