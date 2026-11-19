begin;

-- Browser clients never access HERCO completion objects directly. Restrictive
-- policies also protect this bucket if another application adds a broad policy.
create policy herco_completion_objects_server_only on storage.objects
  as restrictive for all to anon, authenticated
  using (bucket_id <> 'herco-completion') with check (bucket_id <> 'herco-completion');
create policy herco_completion_bucket_server_only on storage.buckets
  as restrictive for all to anon, authenticated
  using (id <> 'herco-completion') with check (id <> 'herco-completion');

create function herco_private.require_private_completion_bucket()
returns void language plpgsql stable set search_path = '' as $$
declare allowed_types text[] := array['image/jpeg','image/png','image/webp'];
begin
  if not exists (
    select 1 from storage.buckets b
    where b.id='herco-completion' and b.public is false
      and b.file_size_limit between 1 and 4194304
      and b.allowed_mime_types @> allowed_types and b.allowed_mime_types <@ allowed_types
  ) then raise exception 'Completion photo storage is unavailable.' using errcode = '55000'; end if;
end;
$$;
revoke all on function herco_private.require_private_completion_bucket() from public, anon, authenticated;

create or replace function public.herco_completion_upload_target(booking uuid)
returns text language plpgsql stable security definer set search_path = '' as $$
begin
  perform herco_private.require_completion_staff();
  if not exists (select 1 from public.herco_bookings b where b.id=booking and b.status='confirmed') then
    raise exception 'This booking cannot accept completion photos.' using errcode = '22023';
  end if;
  perform herco_private.require_private_completion_bucket();
  return booking::text || '/' || auth.uid()::text || '/';
end;
$$;

create or replace function public.herco_completion_photos(booking uuid)
returns text[] language plpgsql stable security definer set search_path = '' as $$
declare paths text[];
begin
  perform herco_private.require_completion_staff();
  select c.photo_paths into paths from herco_private.booking_completion c where c.booking_id=booking;
  if paths is null then return '{}'; end if;
  perform herco_private.require_private_completion_bucket();
  return paths;
end;
$$;

commit;
