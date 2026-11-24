-- F-002: public read of the shop's current default hours and open weekdays (home page and footer).
-- Additive. Returns only open hour, close hour and open weekdays (0 = Sunday ... 6 = Saturday); nothing private.
-- Run on local or staging first. Applying to hosted Supabase is a separate, approved release step.
begin;

create function public.herco_shop_hours()
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('openHour', s.open_hour, 'closeHour', s.close_hour,
    'openWeekdays', to_jsonb(s.open_weekdays))
  from herco_private.schedule_settings as s
$$;

revoke all on function public.herco_shop_hours() from public, anon, authenticated;
grant execute on function public.herco_shop_hours() to anon, authenticated;

commit;
