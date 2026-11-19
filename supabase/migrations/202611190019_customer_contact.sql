begin;

create table public.herco_customer_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '' check (char_length(display_name) <= 120),
  mobile text not null default '' check (
    mobile = '' or (mobile ~ '^\+?[0-9 ()-]{7,20}$' and
      char_length(regexp_replace(mobile, '[^0-9]', '', 'g')) between 7 and 15)
  )
);
alter table public.herco_customer_profiles enable row level security;
revoke all on public.herco_customer_profiles from public, anon, authenticated;
grant select, insert, update on public.herco_customer_profiles to authenticated;
create policy herco_own_contact_read on public.herco_customer_profiles for select to authenticated using (user_id = auth.uid());
create policy herco_own_contact_create on public.herco_customer_profiles for insert to authenticated with check (user_id = auth.uid());
create policy herco_own_contact_update on public.herco_customer_profiles for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

commit;
