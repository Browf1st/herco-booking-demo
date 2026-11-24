-- Staff Customers tab fix.
-- 1) herco_staff_customer_directory and herco_staff_customer_details were STABLE, but
--    herco_private.require_customers_page() runs SELECT ... FOR SHARE. PostgREST runs STABLE functions
--    in a read-only transaction, so every call failed with 25006 (API 503). Both are now VOLATILE.
-- 2) The directory list and its total now include every confirmed customer account, also those
--    with no bookings yet (name, phone and bike are then null). Staff accounts are left out.
-- Same signatures, grants and output fields as 202611190034_staff_ui_parity.sql.
begin;

create or replace function public.herco_staff_customer_details(customer uuid,visit_page integer default 1)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare result jsonb;
begin
  perform herco_private.require_customers_page();
  if visit_page not between 1 and 500 then raise exception 'Choose a valid page.' using errcode='22023'; end if;
  select jsonb_build_object('visits',coalesce(jsonb_agg(record order by created_at desc,id desc),'[]'),
    'hasMore',(select count(*) from public.herco_bookings b where b.customer_id=customer)>visit_page*20) into result
  from (select b.id,b.created_at,herco_private.staff_booking_record(b)-'approval_note'-'private_completion_note' as record
    from public.herco_bookings b where b.customer_id=customer order by b.created_at desc,b.id desc offset (visit_page-1)*20 limit 20) records;
  return result;
end;
$$;

create or replace function public.herco_staff_customer_directory(search_term text default '',after_customer uuid default null)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare matches jsonb;
begin
  perform herco_private.require_customers_page();
  if char_length(coalesce(search_term,''))>254 then raise exception 'Search is too long.' using errcode='22023'; end if;
  select coalesce(jsonb_agg(to_jsonb(record) order by record.id),'[]') into matches from (
    select u.id,u.email,coalesce(nullif(p.display_name,''),latest.name) as name,
      coalesce(nullif(p.mobile,''),latest.phone) as phone,latest.bike,
      (select count(*) from public.herco_bookings b where b.customer_id=u.id) as booking_count,
      (select coalesce(sum(pe.amount),0) from herco_private.point_entries pe where pe.member_id=u.id) as points
    from auth.users u left join public.herco_customer_profiles p on p.user_id=u.id
    left join lateral(select b.customer_contact->>'name' as name,b.customer_contact->>'phone' as phone,b.bike from public.herco_bookings b where b.customer_id=u.id order by b.created_at desc,b.id desc limit 1) latest on true
    where u.email_confirmed_at is not null
      and not exists(select 1 from herco_private.staff_memberships sm where sm.user_id=u.id)
      and (after_customer is null or u.id>after_customer)
      and (coalesce(btrim(search_term),'')='' or position(lower(btrim(search_term)) in lower(concat_ws(' ',u.id::text,u.email,p.display_name,p.mobile,latest.name,latest.phone)))>0)
    order by u.id limit 21
  ) record;
  return jsonb_build_object('customers',matches-20,'nextCursor',case when jsonb_array_length(matches)>20 then matches->19->>'id' end,
    'total',(select count(*) from auth.users u where u.email_confirmed_at is not null
      and not exists(select 1 from herco_private.staff_memberships sm where sm.user_id=u.id)));
end;
$$;

revoke all on function public.herco_staff_customer_details(uuid,integer),public.herco_staff_customer_directory(text,uuid) from public,anon,authenticated;
grant execute on function public.herco_staff_customer_details(uuid,integer),public.herco_staff_customer_directory(text,uuid) to authenticated;
notify pgrst,'reload schema';
commit;
