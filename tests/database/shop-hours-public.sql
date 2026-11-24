-- Public shop hours (202611230004). Run after every migration. Fictional data only.
begin;

-- Anonymous visitor: allowed, gets exactly the three public keys with the default values.
set local role anon;
do $$
declare r jsonb := public.herco_shop_hours();
begin
  if r is null or (select array_agg(k order by k) from jsonb_object_keys(r) as k) <> array['closeHour','openHour','openWeekdays'] then
    raise exception 'Public shop hours returned the wrong keys: %', r; end if;
  if r <> '{"openHour":9,"closeHour":17,"openWeekdays":[0,3,4,5,6]}'::jsonb then
    raise exception 'Default shop hours changed: %', r; end if;
  -- The private table itself stays closed to anon.
  begin
    perform 1 from herco_private.schedule_settings;
    raise exception 'anon could read schedule_settings';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;

-- Signed-in user: allowed, and sees the admin's saved values.
update herco_private.schedule_settings set open_hour = 8, close_hour = 20, open_weekdays = '{1,2}';
set local role authenticated;
do $$
begin
  if public.herco_shop_hours() <> '{"openHour":8,"closeHour":20,"openWeekdays":[1,2]}'::jsonb then
    raise exception 'Saved shop hours not returned: %', public.herco_shop_hours(); end if;
end $$;
reset role;

rollback;
