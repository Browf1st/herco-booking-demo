begin;

do $$
begin
  if exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname in ('public','herco_private') and p.prosecdef
      and not exists (select 1 from pg_options_to_table(p.proconfig) c
        where c.option_name='search_path' and c.option_value in ('','""'))
  ) then raise exception 'A privileged function lacks a fixed empty search_path'; end if;
  if exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname in ('public','herco_private') and p.prosecdef
      and has_function_privilege('anon',p.oid,'EXECUTE')
      and not (n.nspname='public' and p.proname in ('herco_availability','herco_catalog'))
  ) then raise exception 'Unexpected anonymous access to a privileged function'; end if;
end;
$$;

insert into auth.users values
  ('00000000-0000-4000-8000-000000000001','one@example.test',now()),
  ('00000000-0000-4000-8000-000000000002','two@example.test',now());
insert into herco_private.staff_memberships(user_id,role,page_grants,action_grants)
  values ('00000000-0000-4000-8000-000000000002','staff',array['Bookings'],array['completeBooking']);
insert into public.herco_bookings (id,customer_id,request_id,request_payload,visit_date,visit_hour,bike,customer_contact,
  original_services,original_total_centavos,status)
  values ('00000000-0000-4000-8000-000000000003','00000000-0000-4000-8000-000000000001',gen_random_uuid(),'{}',
    current_date,10,'Fixture bike','{}','[{"code":"ceramic","price_centavos":1000}]',1000,'confirmed');
insert into storage.buckets values ('herco-completion',true,4194304,array['image/jpeg','image/png','image/webp']);
insert into storage.objects(bucket_id,name) values
  ('herco-completion','00000000-0000-4000-8000-000000000003/00000000-0000-4000-8000-000000000002/00000000-0000-4000-8000-000000000004.jpg'),
  ('unrelated-bucket','other.jpg');

set local role authenticated;
select set_config('test.uid','00000000-0000-4000-8000-000000000002',true);
select set_config('test.aal','aal1',true);
do $$
begin
  if exists(select 1 from public.herco_bookings) then raise exception 'Cross-customer booking was visible'; end if;
  if exists(select 1 from storage.objects where bucket_id='herco-completion') then
    raise exception 'Browser role can read private evidence directly';
  end if;
  if not exists(select 1 from storage.objects where bucket_id='unrelated-bucket') then
    raise exception 'Completion policy affected an unrelated bucket';
  end if;
  begin
    perform public.herco_completion_upload_target('00000000-0000-4000-8000-000000000003');
    raise exception 'Staff without MFA was authorized';
  exception when insufficient_privilege then null; end;
end;
$$;
select set_config('test.aal','aal2',true);
do $$
begin
  begin
    perform public.herco_completion_upload_target('00000000-0000-4000-8000-000000000003');
    raise exception 'An unsafe public bucket was authorized';
  exception when object_not_in_prerequisite_state then null; end;
end;
$$;

reset role;
update storage.buckets set public=false where id='herco-completion';
set local role authenticated;
do $$
declare
  booking_id uuid := '00000000-0000-4000-8000-000000000003';
  paths text[] := array['00000000-0000-4000-8000-000000000003/00000000-0000-4000-8000-000000000002/00000000-0000-4000-8000-000000000004.jpg'];
begin
  if public.herco_completion_upload_target(booking_id) is distinct from
    '00000000-0000-4000-8000-000000000003/00000000-0000-4000-8000-000000000002/' then
    raise exception 'Authorized staff could not use valid private storage';
  end if;
  begin
    perform public.herco_complete_booking(booking_id,1200,paths,'');
    raise exception 'Completion-only staff could override the finalized price';
  exception when insufficient_privilege then null; end;
  if public.herco_complete_booking(booking_id,1000,paths,'') is null then
    raise exception 'Completion-only staff could not save the finalized price';
  end if;
end;
$$;
select set_config('test.uid','00000000-0000-4000-8000-000000000001',true);
do $$
begin
  if (select count(*) from public.herco_bookings) <> 1 then raise exception 'Owner booking was unavailable'; end if;
end;
$$;

rollback;
