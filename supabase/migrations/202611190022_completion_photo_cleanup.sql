begin;

-- Reservation records prevent a photo from becoming evidence after cleanup has claimed it.
create table herco_private.completion_photo_cleanup (
  path text primary key,
  booking_id uuid not null,
  reserved_at timestamptz not null default clock_timestamp(),
  lease_id uuid not null,
  lease_until timestamptz not null,
  removed_at timestamptz
);
alter table herco_private.completion_photo_cleanup enable row level security;
revoke all on herco_private.completion_photo_cleanup from public, anon, authenticated;
create index herco_completion_cleanup_expired on herco_private.completion_photo_cleanup(lease_until)
  where removed_at is null;
create index herco_completion_photo_paths on herco_private.booking_completion using gin(photo_paths);

create function herco_private.protect_claimed_completion_photos()
returns trigger
language plpgsql set search_path = '' as $$
begin
  -- Coordinate both directions with the same booking row lock.
  perform 1 from public.herco_bookings b where b.id = new.booking_id for update;
  if exists (select 1 from unnest(new.photo_paths) as path where not starts_with(path, new.booking_id::text || '/'))
    or exists (
      select 1 from herco_private.completion_photo_cleanup c where c.path = any(new.photo_paths)
    ) then
    raise exception 'One or more photos expired. Upload them again before completion.' using errcode = '22023';
  end if;
  return new;
end
$$;
create trigger herco_protect_claimed_completion_photos
before insert or update of booking_id, photo_paths on herco_private.booking_completion
for each row execute function herco_private.protect_claimed_completion_photos();

create function public.herco_claim_completion_photo_cleanup(p_retention_days integer, p_limit integer, p_preview boolean)
returns table(object_path text, claim_id uuid, object_exists boolean)
language plpgsql volatile security definer set search_path = '' as $$
declare
  checked_at timestamptz := clock_timestamp();
  cutoff timestamptz;
  batch uuid := gen_random_uuid();
  candidate record;
  claimed_count integer := 0;
  canonical_path text := '^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}/[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}/[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}\.(jpg|png|webp)$';
begin
  if p_retention_days is null or p_retention_days not between 7 and 3650 or p_limit is null
    or p_limit not between 1 and 25 or p_preview is null then
    raise exception 'Check the cleanup retention and batch size.' using errcode = '22023';
  end if;
  cutoff := checked_at - make_interval(days => p_retention_days);
  for candidate in (
    select candidates.path, candidates.booking, candidates.age from (
      select t.path, t.booking_id as booking, t.reserved_at as age
      from herco_private.completion_photo_cleanup t
      where t.removed_at is null and t.lease_until <= checked_at
      union all
      select o.name, case when o.name ~ canonical_path then split_part(o.name, '/', 1)::uuid end, o.created_at
      from storage.objects o
      where o.bucket_id = 'herco-completion' and o.created_at < cutoff and o.name ~ canonical_path
        and not exists (select 1 from herco_private.completion_photo_cleanup t where t.path = o.name)
    ) candidates
    join public.herco_bookings booking on booking.id = candidates.booking
    where not exists (
      select 1 from herco_private.booking_completion c where c.photo_paths @> array[candidates.path]
    )
    order by candidates.age, candidates.path
    limit p_limit * 4
  ) loop
    if not p_preview then
      perform 1 from public.herco_bookings b where b.id = candidate.booking for update skip locked;
      if not found or exists (
        select 1 from herco_private.booking_completion c where c.photo_paths @> array[candidate.path]
      ) then continue; end if;

      insert into herco_private.completion_photo_cleanup as pending(path, booking_id, lease_id, lease_until)
        values (candidate.path, candidate.booking, batch, checked_at + interval '10 minutes')
        on conflict (path) do update
        set lease_id = excluded.lease_id, lease_until = excluded.lease_until
        where pending.removed_at is null and pending.lease_until <= checked_at;
      if not found then continue; end if;
    end if;

    object_path := candidate.path;
    claim_id := case when not p_preview then batch end;
    object_exists := exists (
      select 1 from storage.objects o where o.bucket_id = 'herco-completion' and o.name = candidate.path
    );
    return next;
    claimed_count := claimed_count + 1;
    exit when claimed_count = p_limit;
  end loop;
end
$$;

create function public.herco_confirm_completion_photo_cleanup(p_claim_id uuid)
returns integer
language plpgsql volatile security definer set search_path = '' as $$
declare
  removed integer;
begin
  update herco_private.completion_photo_cleanup t set removed_at = clock_timestamp()
  where t.lease_id = p_claim_id and t.removed_at is null
    and not exists (select 1 from storage.objects o where o.bucket_id = 'herco-completion' and o.name = t.path)
    and not exists (select 1 from herco_private.booking_completion c where c.photo_paths @> array[t.path]);
  get diagnostics removed = row_count;
  return removed;
end
$$;

-- The backup runner needs only the private paths of linked, completed evidence.
create function public.herco_completion_backup_paths(p_after_path text, p_limit integer)
returns table(object_path text)
language plpgsql stable security definer set search_path = '' as $$
begin
  if p_limit is null or p_limit not between 1 and 500 then
    raise exception 'Check the backup batch size.' using errcode = '22023';
  end if;
  return query select distinct path from herco_private.booking_completion c
  cross join lateral unnest(c.photo_paths) as path
  where path > coalesce(p_after_path, '')
  order by path limit p_limit;
end
$$;

revoke all on function herco_private.protect_claimed_completion_photos(),
  public.herco_claim_completion_photo_cleanup(integer, integer, boolean),
  public.herco_confirm_completion_photo_cleanup(uuid), public.herco_completion_backup_paths(text, integer)
from public, anon, authenticated;
grant execute on function public.herco_claim_completion_photo_cleanup(integer, integer, boolean),
  public.herco_confirm_completion_photo_cleanup(uuid), public.herco_completion_backup_paths(text, integer)
to service_role;

commit;
