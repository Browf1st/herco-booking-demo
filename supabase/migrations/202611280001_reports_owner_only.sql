-- Owner decision 2026-11-28: the Reports surface is for the owner only.
-- Report mode now requires role owner/superadmin in addition to the 'Reports' page grant.
-- Staff booking history (report_mode=false) is unchanged. Everything else in this function
-- is a verbatim copy of the version in 202611240001_staff_price_edits.sql.
create or replace function public.herco_staff_booking_records(from_date date,through_date date,search_term text default '',status_filter text default 'all',source_filter text default 'all',record_page integer default 1,report_mode boolean default false,sort_by text default 'date')
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare member herco_private.staff_memberships; items jsonb; metrics jsonb; total integer; show_income boolean; applied_sort text;
  needle text:=lower(btrim(coalesce(search_term,'')));
begin
  if not herco_private.has_verified_staff_session() then raise exception 'Staff access required.' using errcode='42501'; end if;
  select * into member from herco_private.staff_memberships m where m.user_id=auth.uid() and m.enabled;
  if not (case when report_mode then (member.role in ('owner','superadmin') and 'Reports'=any(member.page_grants)) else member.page_grants && array['Booking history','Bookings'] end) then
    raise exception 'You cannot access these booking records.' using errcode='42501'; end if;
  if (from_date is null) <> (through_date is null) or through_date<from_date or through_date-from_date>365
    or record_page is null or record_page not between 1 and 500 or char_length(coalesce(search_term,''))>254
    or status_filter not in ('all','pending','confirmed','done','cancelled') or source_filter not in ('all','online','walk-in')
    or sort_by is null or sort_by not in ('date','date_asc','price','price_asc','status') then
    raise exception 'Check record filters and use up to 366 days.' using errcode='22023'; end if;
  show_income:='viewIncome'=any(member.action_grants);
  applied_sort:=case when sort_by in ('price','price_asc') and not show_income then 'date' else sort_by end;
  with filtered as (
    select b.* from public.herco_bookings b where (from_date is null or b.visit_date between from_date and through_date
      or (report_mode and exists(select 1 from herco_private.booking_completion c where c.booking_id=b.id and (c.completed_at at time zone 'Asia/Manila')::date between from_date and through_date)))
      and (source_filter='all' or (source_filter='walk-in')=(b.booking_kind='walk_in'))
      and herco_private.booking_matches_search(b,needle)
  ) select jsonb_build_object('total',count(*),'pending',count(*) filter(where status='pending'),'booked',count(*) filter(where status='confirmed'),
    'completed',count(*) filter(where status='done'),'cancelled',count(*) filter(where status='cancelled'),'walkIns',count(*) filter(where booking_kind='walk_in')),
    count(*) filter(where status_filter='all' or status=status_filter) into metrics,total from filtered;
  -- One ordering for every page: the chosen sort first, then date, then id so pages never repeat or skip a row.
  -- Rank on keys only (id + sort columns), keep the 20 ids of this page, and only then build the JSON for those rows.
  with ranked as (
    select b.id,
      row_number() over (order by
        case when applied_sort='status' then case b.status when 'pending' then 0 when 'confirmed' then 1 when 'done' then 2 else 3 end end asc,
        case when applied_sort='price' then case when b.status='done' then coalesce(correction.value,c.final_price_centavos) else coalesce(b.current_total_centavos,b.original_total_centavos) end end desc nulls last,
        case when applied_sort='price_asc' then case when b.status='done' then coalesce(correction.value,c.final_price_centavos) else coalesce(b.current_total_centavos,b.original_total_centavos) end end asc nulls last,
        case when applied_sort='date_asc' then b.visit_date end asc,
        case when applied_sort='date_asc' then b.created_at end asc,
        case when applied_sort='date_asc' then b.id end asc,
        b.visit_date desc,b.created_at desc,b.id desc) as pos
    from public.herco_bookings b left join herco_private.booking_completion c on c.booking_id=b.id
    left join lateral(select p.corrected_completed_centavos as value from herco_private.booking_price_corrections p where p.booking_id=b.id and p.corrected_completed_centavos is not null order by p.revision desc limit 1) correction on true
    where (from_date is null or b.visit_date between from_date and through_date
      or (report_mode and (c.completed_at at time zone 'Asia/Manila')::date between from_date and through_date)) and (status_filter='all' or b.status=status_filter)
      and (source_filter='all' or (source_filter='walk-in')=(b.booking_kind='walk_in'))
      and herco_private.booking_matches_search(b,needle)
  ), page as (
    select r.id,r.pos from ranked r where r.pos>(record_page-1)*20 and r.pos<=record_page*20
  ) select coalesce(jsonb_agg(
      herco_private.staff_booking_record(b)||case when show_income then jsonb_build_object(
        'final_price_centavos',coalesce(correction.value,c.final_price_centavos),
        'original_total_centavos',b.original_total_centavos)
      else jsonb_build_object('final_price_centavos',null,'original_total_centavos',null,'total_centavos',null,
        'original_services',herco_private.strip_service_money(b.original_services),
        'current_services',herco_private.strip_service_money(coalesce(b.current_services,b.original_services))) end
      order by page.pos),'[]') into items
    from page join public.herco_bookings b on b.id=page.id
    left join herco_private.booking_completion c on c.booking_id=b.id
    left join lateral(select p.corrected_completed_centavos as value from herco_private.booking_price_corrections p where p.booking_id=b.id and p.corrected_completed_centavos is not null order by p.revision desc limit 1) correction on true;
  if report_mode then
    select metrics || jsonb_build_object('completedValueCentavos',case when show_income then coalesce(sum(coalesce(correction.value,c.final_price_centavos)) filter(where b.status='done'),0) end,
      'completed',count(*) filter(where b.status='done'), 'completedWithoutValue',count(*) filter(where b.status='done' and c.booking_id is null)) into metrics
    from public.herco_bookings b left join herco_private.booking_completion c on c.booking_id=b.id
    left join lateral(select p.corrected_completed_centavos as value from herco_private.booking_price_corrections p where p.booking_id=b.id and p.corrected_completed_centavos is not null order by p.revision desc limit 1) correction on true
    where (from_date is null or coalesce((c.completed_at at time zone 'Asia/Manila')::date,b.visit_date) between from_date and through_date)
      and (status_filter='all' or b.status=status_filter) and (source_filter='all' or (source_filter='walk-in')=(b.booking_kind='walk_in'))
      and herco_private.booking_matches_search(b,needle);
  end if;
  return jsonb_build_object('records',items,'metrics',metrics,'total',total,'page',record_page,'pages',greatest(1,ceil(total/20.0)),'canViewIncome',show_income,'sort',applied_sort);
end;
$$;
