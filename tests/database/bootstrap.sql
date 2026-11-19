-- Run only against a fresh local or CI database. Simulate the Supabase objects
-- the migrations use, with no live account or booking data.
create role anon;
create role authenticated;
create role service_role bypassrls;
create schema auth;
create table auth.users(id uuid primary key,email text,email_confirmed_at timestamptz);
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('test.uid',true),'')::uuid
$$;
create function auth.jwt() returns jsonb language sql stable as $$
  select jsonb_build_object('aal',current_setting('test.aal',true))
$$;
grant usage on schema auth to anon, authenticated, service_role;

create schema storage;
create table storage.buckets(id text primary key, public boolean, file_size_limit bigint, allowed_mime_types text[]);
create table storage.objects(id uuid primary key default gen_random_uuid(),bucket_id text,name text,created_at timestamptz default now());
alter table storage.buckets enable row level security;
alter table storage.objects enable row level security;
grant usage on schema storage to anon, authenticated;
grant select, insert, update, delete on storage.buckets, storage.objects to anon, authenticated;
-- Simulate an unrelated permissive policy so the restrictive completion policy is exercised.
create policy test_other_bucket_read on storage.buckets for select to anon,authenticated using (true);
create policy test_other_object_access on storage.objects for all to anon,authenticated using (true) with check (true);
