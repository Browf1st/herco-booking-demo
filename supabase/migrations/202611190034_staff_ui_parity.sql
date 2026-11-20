-- Restore the demo's staff projections without exposing private records to customers.
begin;

create table herco_private.booking_customer_shares (
  booking_id uuid primary key references public.herco_bookings(id),
  note text not null default '' check (char_length(note)<=1000),
  photo_paths text[] not null default '{}' check(cardinality(photo_paths)<=3),
  shared_by uuid not null references auth.users(id),
  shared_at timestamptz not null default now()
);
alter table herco_private.booking_customer_shares enable row level security;
revoke all on herco_private.booking_customer_shares from public,anon,authenticated;

create function public.herco_share_booking_details(booking uuid, shared_note text, share_photos boolean)
returns void language plpgsql volatile security definer set search_path='' as $$
declare grants text[]:=herco_private.staff_booking_grants(); photos text[];
begin
  if not (grants && array['editServices','completeBooking']) then
    raise exception 'Sharing requires booking editing permission.' using errcode='42501';
  end if;
  if shared_note is null or char_length(shared_note)>1000 or share_photos is null then
    raise exception 'Check the customer message.' using errcode='22023';
  end if;
  perform 1 from public.herco_bookings b where b.id=booking for update;
  if not found then raise exception 'Booking not found.' using errcode='P0002'; end if;
  if share_photos then select c.photo_paths into photos from herco_private.booking_completion c where c.booking_id=booking; end if;
  insert into herco_private.booking_customer_shares(booking_id,note,photo_paths,shared_by)
  values(booking,btrim(shared_note),coalesce(photos,'{}'),auth.uid())
  on conflict(booking_id) do update set note=excluded.note,photo_paths=excluded.photo_paths,shared_by=excluded.shared_by,shared_at=now();
  insert into public.herco_booking_events(booking_id,actor_id,kind,to_status)
    select booking,auth.uid(),'customer_details_shared',b.status from public.herco_bookings b where b.id=booking;
end;
$$;

create function public.herco_customer_booking_shared(booking uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
  if auth.uid() is null or not exists(select 1 from public.herco_bookings b where b.id=booking and b.customer_id=auth.uid()) then
    raise exception 'Booking not found.' using errcode='42501';
  end if;
  return coalesce((select jsonb_build_object('note',s.note,'photo_paths',s.photo_paths,'shared_at',s.shared_at)
    from herco_private.booking_customer_shares s where s.booking_id=booking),jsonb_build_object('note','','photo_paths','[]'::jsonb));
end;
$$;

create function herco_private.staff_booking_record(booking public.herco_bookings)
returns jsonb language sql stable set search_path='' as $$
  select jsonb_build_object('id',booking.id,'reference','HG-'||booking.reference_no::text,
    'visit_date',booking.visit_date,'visit_hour',booking.visit_hour,'bike',booking.bike,
    'customer_id',booking.customer_id,'customer_name',booking.customer_contact->>'name',
    'customer_phone',booking.customer_contact->>'phone','customer_email',booking.customer_contact->>'email',
    'plate',booking.customer_contact->>'plate','status',booking.status,'created_at',booking.created_at,
    'source',case when booking.booking_kind='walk_in' then 'walk-in' else 'online' end,
    'original_services',booking.original_services,'current_services',coalesce(booking.current_services,booking.original_services),
    'total_centavos',coalesce(booking.current_total_centavos,booking.original_total_centavos),
    'services',(select coalesce(jsonb_agg(s->>'label'),'[]') from jsonb_array_elements(coalesce(booking.current_services,booking.original_services)) s),
    'coating_options',booking.coating_options,
    'approved_at',(select min(e.created_at) from public.herco_booking_events e where e.booking_id=booking.id and e.kind in ('booking_confirmed','walk_in_confirmed')),
    'completed_at',c.completed_at,'private_completion_note',c.note,'approval_note',n.body,
    'shared_note',coalesce(sh.note,''),'shared_photos',coalesce(cardinality(sh.photo_paths),0),
    'photo_count',coalesce(cardinality(c.photo_paths),0),
    'request_pending',exists(select 1 from herco_private.booking_change_requests r where r.booking_id=booking.id and r.state='pending'))
  from (select 1) singleton
  left join herco_private.booking_completion c on c.booking_id=booking.id
  left join herco_private.booking_approval_notes n on n.booking_id=booking.id
  left join herco_private.booking_customer_shares sh on sh.booking_id=booking.id;
$$;

create or replace function public.herco_staff_booking_day_with_options(visit_date date)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare result jsonb:=public.herco_staff_booking_day(visit_date); items jsonb;
begin
  select coalesce(jsonb_agg(herco_private.staff_booking_record(b) order by b.visit_hour nulls first,b.created_at),'[]') into items
  from public.herco_bookings b where b.visit_date=herco_staff_booking_day_with_options.visit_date and b.status<>'cancelled';
  return jsonb_set(result,'{bookings}',items);
end;
$$;

create function public.herco_staff_calendar(from_date date,through_date date)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare result jsonb;
begin
  perform herco_private.staff_booking_grants();
  if from_date is null or through_date is null or through_date<from_date or through_date-from_date>62 then
    raise exception 'Choose up to 63 calendar dates.' using errcode='22023';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('date',day::date,
    'pending',(select count(*) from public.herco_bookings b where b.visit_date=day::date and b.status='pending'),
    'booked',(select count(*) from public.herco_bookings b where b.visit_date=day::date and b.status='confirmed'),
    'completed',(select count(*) from public.herco_bookings b where b.visit_date=day::date and b.status='done'),
    'closed',not coalesce((select o.is_open from herco_private.date_overrides o where o.visit_date=day::date),extract(isodow from day) not in (1,2))) order by day),'[]') into result
  from generate_series(from_date::timestamp,through_date::timestamp,'1 day'::interval) day;
  return result;
end;
$$;

create function public.herco_staff_booking_change_cards(skip integer default 0)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare result jsonb;
begin
  select coalesce(jsonb_agg(to_jsonb(r)||jsonb_build_object('booking',herco_private.staff_booking_record(b))),'[]') into result
  from public.herco_staff_booking_changes(skip) r join public.herco_bookings b on b.id=r.booking_id;
  return result;
end;
$$;

create function public.herco_staff_booking_records(from_date date,through_date date,search_term text default '',status_filter text default 'all',source_filter text default 'all',record_page integer default 1,report_mode boolean default false)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare member herco_private.staff_memberships; items jsonb; metrics jsonb; total integer; show_income boolean;
begin
  if not herco_private.has_verified_staff_session() then raise exception 'Staff access required.' using errcode='42501'; end if;
  select * into member from herco_private.staff_memberships m where m.user_id=auth.uid() and m.enabled;
  if not (case when report_mode then 'Reports'=any(member.page_grants) else member.page_grants && array['Booking history','Bookings'] end) then
    raise exception 'You cannot access these booking records.' using errcode='42501'; end if;
  if (from_date is null) <> (through_date is null) or through_date<from_date or through_date-from_date>365
    or record_page is null or record_page not between 1 and 500 or char_length(coalesce(search_term,''))>254
    or status_filter not in ('all','pending','confirmed','done','cancelled') or source_filter not in ('all','online','walk-in') then
    raise exception 'Check record filters and use up to 366 days.' using errcode='22023'; end if;
  show_income:='viewIncome'=any(member.action_grants);
  with filtered as (
    select b.* from public.herco_bookings b where (from_date is null or b.visit_date between from_date and through_date
      or (report_mode and exists(select 1 from herco_private.booking_completion c where c.booking_id=b.id and (c.completed_at at time zone 'Asia/Manila')::date between from_date and through_date)))
      and (source_filter='all' or (source_filter='walk-in')=(b.booking_kind='walk_in'))
      and (coalesce(btrim(search_term),'')='' or position(lower(btrim(search_term)) in lower(concat_ws(' ',b.id::text,'HG-'||b.reference_no::text,b.bike,b.customer_contact::text,b.original_services::text)))>0)
  ) select jsonb_build_object('total',count(*),'pending',count(*) filter(where status='pending'),'booked',count(*) filter(where status='confirmed'),
    'completed',count(*) filter(where status='done'),'cancelled',count(*) filter(where status='cancelled'),'walkIns',count(*) filter(where booking_kind='walk_in')),
    count(*) filter(where status_filter='all' or status=status_filter) into metrics,total from filtered;
  select coalesce(jsonb_agg(record order by visit_date desc,created_at desc,id desc),'[]') into items from (
    select b.id,b.visit_date,b.created_at,herco_private.staff_booking_record(b)||jsonb_build_object('final_price_centavos',
      case when show_income then coalesce((select p.corrected_completed_centavos from herco_private.booking_price_corrections p where p.booking_id=b.id and p.corrected_completed_centavos is not null order by p.revision desc limit 1),c.final_price_centavos) end) as record
    from public.herco_bookings b left join herco_private.booking_completion c on c.booking_id=b.id
    where (from_date is null or b.visit_date between from_date and through_date
      or (report_mode and (c.completed_at at time zone 'Asia/Manila')::date between from_date and through_date)) and (status_filter='all' or b.status=status_filter)
      and (source_filter='all' or (source_filter='walk-in')=(b.booking_kind='walk_in'))
      and (coalesce(btrim(search_term),'')='' or position(lower(btrim(search_term)) in lower(concat_ws(' ',b.id::text,'HG-'||b.reference_no::text,b.bike,b.customer_contact::text,b.original_services::text)))>0)
    order by b.visit_date desc,b.created_at desc,b.id desc offset (record_page-1)*20 limit 20
  ) records;
  if report_mode then
    select metrics || jsonb_build_object('completedValueCentavos',case when show_income then coalesce(sum(coalesce(correction.value,c.final_price_centavos)) filter(where b.status='done'),0) end,
      'completed',count(*) filter(where b.status='done'), 'completedWithoutValue',count(*) filter(where b.status='done' and c.booking_id is null)) into metrics
    from public.herco_bookings b left join herco_private.booking_completion c on c.booking_id=b.id
    left join lateral(select p.corrected_completed_centavos as value from herco_private.booking_price_corrections p where p.booking_id=b.id and p.corrected_completed_centavos is not null order by p.revision desc limit 1) correction on true
    where (from_date is null or coalesce((c.completed_at at time zone 'Asia/Manila')::date,b.visit_date) between from_date and through_date)
      and (status_filter='all' or b.status=status_filter) and (source_filter='all' or (source_filter='walk-in')=(b.booking_kind='walk_in'))
      and (coalesce(btrim(search_term),'')='' or position(lower(btrim(search_term)) in lower(concat_ws(' ',b.id::text,'HG-'||b.reference_no::text,b.bike,b.customer_contact::text,b.original_services::text)))>0);
  end if;
  return jsonb_build_object('records',items,'metrics',metrics,'total',total,'page',record_page,'pages',greatest(1,ceil(total/20.0)),'canViewIncome',show_income);
end;
$$;

create function public.herco_staff_customer_details(customer uuid,visit_page integer default 1)
returns jsonb language plpgsql stable security definer set search_path='' as $$
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

create function public.herco_staff_customer_directory(search_term text default '',after_customer uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
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
    cross join lateral(select b.customer_contact->>'name' as name,b.customer_contact->>'phone' as phone,b.bike from public.herco_bookings b where b.customer_id=u.id order by b.created_at desc,b.id desc limit 1) latest
    where u.email_confirmed_at is not null and (after_customer is null or u.id>after_customer)
      and (coalesce(btrim(search_term),'')='' or position(lower(btrim(search_term)) in lower(concat_ws(' ',u.id::text,u.email,p.display_name,p.mobile,latest.name,latest.phone)))>0)
    order by u.id limit 21
  ) record;
  return jsonb_build_object('customers',matches-20,'nextCursor',case when jsonb_array_length(matches)>20 then matches->19->>'id' end,
    'total',(select count(*) from auth.users u where u.email_confirmed_at is not null
      and exists(select 1 from public.herco_bookings b where b.customer_id=u.id)));
end;
$$;

create function public.herco_staff_activity_labels(from_date date,through_date date)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
  select coalesce(jsonb_agg(to_jsonb(a)||jsonb_build_object('actor_label',coalesce(nullif(p.display_name,''),u.email,a.actor::text)) order by a.recorded_at desc),'[]') into result
  from public.herco_staff_activity(from_date,through_date) a
  left join auth.users u on u.id=a.actor
  left join public.herco_customer_profiles p on p.user_id=a.actor;
  return result;
end;
$$;

-- Counters beside the Booking menu entries, matching the demo's pending badges.
create function public.herco_staff_pending_counts()
returns jsonb language plpgsql volatile security definer set search_path='' as $$
begin
  perform herco_private.staff_booking_grants();
  return jsonb_build_object(
    'bookings',(select count(*) from public.herco_bookings b where b.status='pending'),
    'requests',(select count(*) from herco_private.booking_change_requests r where r.state='pending'));
end;
$$;
revoke all on function public.herco_staff_pending_counts() from public,anon,authenticated;
grant execute on function public.herco_staff_pending_counts() to authenticated;

revoke all on function herco_private.staff_booking_record(public.herco_bookings) from public,anon,authenticated;
revoke all on function public.herco_share_booking_details(uuid,text,boolean),public.herco_customer_booking_shared(uuid),public.herco_staff_calendar(date,date),public.herco_staff_booking_records(date,date,text,text,text,integer,boolean),public.herco_staff_customer_details(uuid,integer),public.herco_staff_customer_directory(text,uuid),public.herco_staff_activity_labels(date,date) from public,anon,authenticated;
grant execute on function public.herco_share_booking_details(uuid,text,boolean),public.herco_customer_booking_shared(uuid),public.herco_staff_calendar(date,date),public.herco_staff_booking_records(date,date,text,text,text,integer,boolean),public.herco_staff_customer_details(uuid,integer),public.herco_staff_customer_directory(text,uuid),public.herco_staff_activity_labels(date,date) to authenticated;
revoke all on function public.herco_staff_booking_change_cards(integer) from public,anon,authenticated;
grant execute on function public.herco_staff_booking_change_cards(integer) to authenticated;
notify pgrst,'reload schema';
commit;
