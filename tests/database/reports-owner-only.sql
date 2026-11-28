-- Owner decision 2026-11-28: Reports (report_mode=true) is owner/superadmin only, even with the 'Reports' page grant.
-- Fictional data only; rolled back.
begin;

create function public.herco_test_refused(statement text, state text) returns void language plpgsql as $$
begin
  execute statement;
  raise exception 'NOT REFUSED: %', statement;
exception when others then
  if sqlstate is distinct from state then
    raise exception 'Expected % but got % (%) for: %', state, sqlstate, sqlerrm, statement;
  end if;
end $$;

insert into auth.users(id,email,email_confirmed_at) values
  ('00000000-0000-4000-8000-0000000004b1','reports-owner@example.test',now()),
  ('00000000-0000-4000-8000-0000000004b2','reports-admin@example.test',now());
-- Owner with the Reports grant; and an admin who also holds the Reports grant but is not an owner.
insert into herco_private.staff_memberships(user_id,role,page_grants,action_grants) values
  ('00000000-0000-4000-8000-0000000004b1','owner',array['Reports','Bookings'],array['viewIncome']),
  ('00000000-0000-4000-8000-0000000004b2','admin',array['Reports','Bookings'],array['viewIncome']);

set local role authenticated;

-- 1. Owner can open Reports.
select set_config('test.uid','00000000-0000-4000-8000-0000000004b1',true);
do $$
declare result jsonb := public.herco_staff_booking_records(current_date,current_date,'','all','all',1,true,'date');
begin
  if result->'records' is null then raise exception 'Owner was not given a Reports result: %', result; end if;
end $$;

-- 2. A non-owner admin WITH the Reports grant is refused report_mode, but can still read booking history.
select set_config('test.uid','00000000-0000-4000-8000-0000000004b2',true);
select public.herco_test_refused($s$select public.herco_staff_booking_records(current_date,current_date,'','all','all',1,true,'date')$s$,'42501');
do $$
declare result jsonb := public.herco_staff_booking_records(current_date,current_date,'','all','all',1,false,'date');
begin
  if result->'records' is null then raise exception 'Admin lost Booking history access: %', result; end if;
end $$;

reset role;
rollback;
