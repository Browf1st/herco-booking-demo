begin;

-- Create the private herco-completion bucket via Storage administration.
-- Only the server Storage client uploads files. The database reads object metadata for verification.
create table herco_private.booking_completion (
  booking_id uuid primary key references public.herco_bookings(id),
  actor_id uuid not null references auth.users(id),
  completed_at timestamptz not null default now(),
  final_price_centavos bigint not null check (final_price_centavos >= 0),
  photo_paths text[] not null check (cardinality(photo_paths) between 1 and 3),
  note text not null check (char_length(note) <= 500)
);
alter table herco_private.booking_completion enable row level security;
revoke all on herco_private.booking_completion from public, anon, authenticated;

create function herco_private.require_completion_staff()
returns void language plpgsql stable set search_path = '' as $$
begin
  if (auth.jwt()->>'aal') is distinct from 'aal2' or not exists (
    select 1 from herco_private.staff_memberships s where s.user_id = auth.uid() and s.enabled
      and s.page_grants && array['Bookings', 'Booking history']
      and 'completeBooking' = any(s.action_grants)
  ) then raise exception 'Staff completion permission and MFA are required.' using errcode = '42501'; end if;
end;
$$;
revoke all on function herco_private.require_completion_staff() from public, anon, authenticated;

create function public.herco_completion_upload_target(booking uuid)
returns text language plpgsql stable security definer set search_path = '' as $$
begin
  perform herco_private.require_completion_staff();
  if not exists (select 1 from public.herco_bookings b where b.id = booking and b.status = 'confirmed') then
    raise exception 'This booking cannot accept completion photos.' using errcode = '22023';
  end if;
  return booking::text || '/' || auth.uid()::text || '/';
end;
$$;

create function public.herco_complete_booking(booking uuid, price_centavos bigint, photos text[], completion_note text)
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
  if current_booking.original_services = '[]'::jsonb or exists (
    select 1 from jsonb_array_elements(current_booking.original_services) s
    where jsonb_typeof(s->'price_centavos') is distinct from 'number'
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

create function public.herco_booking_report(from_date date, to_date date)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare actions text[];
  include_value boolean;
begin
  if (auth.jwt()->>'aal') is distinct from 'aal2' then
    raise exception 'Reports require staff permission and MFA.' using errcode = '42501';
  end if;
  select s.action_grants into actions from herco_private.staff_memberships s
    where s.user_id = auth.uid() and s.enabled and 'Reports' = any(s.page_grants);
  if not found then raise exception 'This account cannot access reports.' using errcode = '42501'; end if;
  if from_date is null or to_date is null or to_date < from_date or to_date - from_date > 365 then
    raise exception 'Choose a date range of up to 366 days.' using errcode = '22023';
  end if;
  include_value := 'viewIncome' = any(actions);
  return (select jsonb_build_object(
    'total', count(*), 'pending', count(*) filter (where status = 'pending'),
    'booked', count(*) filter (where status = 'confirmed'), 'cancelled', count(*) filter (where status = 'cancelled'),
    'completed', count(*) filter (where status = 'done'),
    'completedWithoutValue', case when include_value then count(*) filter (where status = 'done' and c.booking_id is null) else null end,
    'completedValueCentavos', case when include_value then coalesce(sum(c.final_price_centavos) filter (where status = 'done'), 0) else null end
  ) from public.herco_bookings b left join herco_private.booking_completion c on c.booking_id = b.id
    where b.visit_date between from_date and to_date);
end;
$$;

create function public.herco_completion_photos(booking uuid)
returns text[] language plpgsql stable security definer set search_path = '' as $$
begin
  perform herco_private.require_completion_staff();
  return coalesce((select c.photo_paths from herco_private.booking_completion c where c.booking_id = booking), '{}');
end;
$$;

create function public.herco_workspace_permissions()
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('pages', s.page_grants, 'actions', s.action_grants)
  from herco_private.staff_memberships s
  where s.enabled and s.user_id = auth.uid() and auth.jwt()->>'aal' = 'aal2';
$$;

revoke all on function public.herco_completion_upload_target(uuid),
  public.herco_complete_booking(uuid, bigint, text[], text), public.herco_booking_report(date, date),
  public.herco_completion_photos(uuid), public.herco_workspace_permissions()
  from public, anon, authenticated;
grant execute on function public.herco_completion_upload_target(uuid),
  public.herco_complete_booking(uuid, bigint, text[], text), public.herco_booking_report(date, date),
  public.herco_completion_photos(uuid), public.herco_workspace_permissions()
  to authenticated;

commit;
