begin;

-- F-007 "Price changes and added services after inspection" and F-011 revisions (owner 2026-11-24).
-- 1. Staff change the price of one service line on a Pending or Booked booking (grant adjustPrices, checked here).
-- 2. One read, herco_booking_history, for the More details popup: price changes, added/removed services,
--    price corrections after Done and booking status events, newest first.
-- 3. Reports sort gains "date_asc" and "price_asc", and the text search no longer matches price digits
--    for staff without viewIncome.
-- Adding and removing services reuses the existing herco_save_booked_services (grant editServices). Nothing here
-- changes original_services, original_total_centavos or any earlier table.

create table herco_private.booking_price_edits (
  booking_id uuid not null references public.herco_bookings(id),
  revision integer not null,
  actor_id uuid not null references auth.users(id),
  request_id uuid not null,
  service_code text not null,
  service_label text not null,
  previous_centavos bigint check (previous_centavos >= 0),
  new_centavos bigint not null check (new_centavos between 0 and 100000000 and new_centavos % 100 = 0),
  reason text not null check (char_length(reason) between 1 and 200),
  -- The whole line as it was before the change (with its details and promotion), so nothing is lost when they are dropped.
  previous_line jsonb,
  recorded_at timestamptz not null default clock_timestamp(),
  primary key (booking_id, revision),
  unique (booking_id, actor_id, request_id)
);
alter table herco_private.booking_price_edits enable row level security;
revoke all on herco_private.booking_price_edits from public, anon, authenticated;

-- Changes one service line. Needs adjustPrices AND viewIncome (the price check below would otherwise let a caller
-- guess prices). Errors: 42501 no grant, P0002 booking missing, 22023 bad input, P0400 the price is already that price,
-- P0423 booking is not Pending or Booked, P0412 the line changed since the caller read it.
-- expected_price_centavos is the line's stored price_centavos as read; a line with no price (quote-only, stored as
-- 0 or without price_centavos) is matched by 0 or null. The new line loses max_centavos, quote_required, details and
-- promotion (they no longer add up); the full old line is kept in booking_price_edits.previous_line.
create function public.herco_staff_set_line_price(booking uuid, request_id uuid, service_code text,
  expected_price_centavos bigint, new_price_centavos bigint, reason text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  b public.herco_bookings;
  earlier herco_private.booking_price_edits;
  lines jsonb;
  line jsonb;
  revised jsonb;
  old_price bigint;
  quote_line boolean;
  new_total bigint;
  note text := btrim(coalesce(reason, ''));
begin
  perform herco_private.require_price_adjustment();
  perform 1 from herco_private.staff_memberships s where s.user_id = auth.uid() and s.enabled
    and 'viewIncome' = any(s.action_grants) for share;
  if not found then raise exception 'Changing prices requires permission to view income.' using errcode = '42501'; end if;
  if booking is null or request_id is null or service_code is null or char_length(service_code) not between 1 and 100
    or new_price_centavos is null or new_price_centavos not between 0 and 100000000 or new_price_centavos % 100 <> 0
    or (expected_price_centavos is not null and expected_price_centavos < 0)
    or char_length(note) not between 1 and 200 then
    raise exception 'Enter a whole-peso price from 0 to 1,000,000 and a reason of up to 200 characters.' using errcode = '22023';
  end if;
  select x.* into b from public.herco_bookings x where x.id = booking for update;
  if not found then raise exception 'Booking not found.' using errcode = 'P0002'; end if;

  -- A repeated request (same staff member and request id) is answered from the saved change, even if the booking has moved on.
  select e.* into earlier from herco_private.booking_price_edits e
    where e.booking_id = b.id and e.actor_id = auth.uid() and e.request_id = herco_staff_set_line_price.request_id;
  if found then
    if earlier.service_code <> service_code or earlier.new_centavos <> new_price_centavos or earlier.reason <> note
      or coalesce(earlier.previous_centavos, 0) <> coalesce(expected_price_centavos, 0) then
      raise exception 'This request ID belongs to another price change.' using errcode = '22023';
    end if;
    return jsonb_build_object('revision', b.service_revision, 'status', b.status,
      'lines', coalesce(b.current_services, b.original_services),
      'totalCentavos', coalesce(b.current_total_centavos, b.original_total_centavos));
  end if;

  if b.status not in ('pending', 'confirmed') then
    raise exception 'This booking can no longer be changed.' using errcode = 'P0423';
  end if;
  lines := coalesce(b.current_services, b.original_services);
  select item into line from jsonb_array_elements(lines) item where item->>'code' = service_code limit 1;
  if line is null then
    raise exception 'This service changed. Reload and try again.' using errcode = 'P0412';
  end if;
  -- A quote-only line is stored with price 0 or no price; it is matched by 0 or null.
  old_price := coalesce((line->>'price_centavos')::bigint, 0);
  quote_line := coalesce((line->>'quote_required')::boolean, false) or not (line ? 'price_centavos');
  if old_price <> coalesce(expected_price_centavos, 0) then
    raise exception 'This service price changed. Reload and try again.' using errcode = 'P0412';
  end if;
  -- Pricing a quote line at 0 is allowed (it clears the quote flag); any other same price is refused.
  if old_price = new_price_centavos and not quote_line then
    raise exception 'That is already the price.' using errcode = 'P0400';
  end if;

  select jsonb_agg(case when item->>'code' = service_code
      then (item - 'max_centavos' - 'quote_required' - 'details' - 'promotion') || jsonb_build_object('price_centavos', new_price_centavos)
      else item end order by pos)
    into revised from jsonb_array_elements(lines) with ordinality as l(item, pos);
  select coalesce(sum((item->>'price_centavos')::bigint), 0) into new_total from jsonb_array_elements(revised) item;

  -- current_services and current_total_centavos are always written together.
  update public.herco_bookings set current_services = revised, current_total_centavos = new_total,
    service_revision = b.service_revision + 1 where id = b.id;
  insert into herco_private.booking_price_edits (booking_id, revision, actor_id, request_id, service_code, service_label,
    previous_centavos, new_centavos, reason, previous_line)
    values (b.id, b.service_revision + 1, auth.uid(), request_id, service_code, coalesce(line->>'label', service_code),
      case when quote_line then null else old_price end, new_price_centavos, note, line);
  insert into public.herco_booking_events (booking_id, actor_id, kind, to_status)
    values (b.id, auth.uid(), 'booking_line_price_changed', b.status);
  return jsonb_build_object('revision', b.service_revision + 1, 'status', b.status, 'lines', revised, 'totalCentavos', new_total);
end;
$$;

-- History for the More details popup. Staff only (Bookings, Booking history or Reports page). Newest first, at most 200 entries.
-- Without viewIncome no amount is returned. Never returns notes, emails or phone numbers.
create function public.herco_booking_history(booking uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  member herco_private.staff_memberships;
  b public.herco_bookings;
  show_money boolean;
  result jsonb;
begin
  if not herco_private.has_verified_staff_session() then
    raise exception 'Sign in with a verified staff account first.' using errcode = '42501';
  end if;
  select m.* into member from herco_private.staff_memberships m where m.user_id = auth.uid() and m.enabled
    and m.page_grants && array['Bookings', 'Booking history', 'Reports'];
  if not found then raise exception 'You cannot access booking history.' using errcode = '42501'; end if;
  if booking is null then raise exception 'Choose a booking.' using errcode = '22023'; end if;
  select x.* into b from public.herco_bookings x where x.id = booking;
  if not found then raise exception 'Booking not found.' using errcode = 'P0002'; end if;
  show_money := 'viewIncome' = any(member.action_grants);

  select coalesce(jsonb_agg(top.entry order by top.happened desc, top.src desc, top.seq desc), '[]'::jsonb) into result from (
    select r.happened, r.src, r.seq,
      jsonb_strip_nulls(jsonb_build_object('at', r.happened, 'kind', r.kind,
        'actor', case when sm.user_id is not null then coalesce(nullif(sm.display_name, ''), nullif(cp.display_name, ''), 'HERCO staff')
          else 'Customer' end,
        'service_code', r.service_code, 'service_label', r.service_label, 'reason', r.reason)
        || case when show_money then jsonb_build_object('from_centavos', r.old_c, 'to_centavos', r.new_c) else '{}'::jsonb end) as entry
    from (
      select e.recorded_at as happened, 1 as src, e.revision::bigint as seq, e.actor_id, 'price_changed'::text as kind,
        e.service_code, e.service_label, e.previous_centavos as old_c, e.new_centavos as new_c, e.reason
      from herco_private.booking_price_edits e where e.booking_id = b.id
      union all
      select c.recorded_at, 2, c.revision::bigint, c.actor_id, 'price_corrected', c.service_code,
        coalesce((select l->>'label' from jsonb_array_elements(coalesce(b.current_services, b.original_services)) l where l->>'code' = c.service_code limit 1),
          (select l->>'label' from jsonb_array_elements(b.original_services) l where l->>'code' = c.service_code limit 1), c.service_code),
        c.previous_centavos, c.corrected_centavos, c.reason
      from herco_private.booking_price_corrections c where c.booking_id = b.id
      union all
      select s.recorded_at, 3, s.revision::bigint, s.actor_id, 'service_added', a->>'code', coalesce(a->>'label', a->>'code'),
        null::bigint, (a->>'price_centavos')::bigint, null::text
      from herco_private.booking_service_changes s cross join lateral jsonb_array_elements(s.after_services) a
      where s.booking_id = b.id
        and not exists (select 1 from jsonb_array_elements(s.before_services) o where o->>'code' = a->>'code')
      union all
      select s.recorded_at, 3, s.revision::bigint, s.actor_id, 'service_removed', o->>'code', coalesce(o->>'label', o->>'code'),
        (o->>'price_centavos')::bigint, null::bigint, null::text
      from herco_private.booking_service_changes s cross join lateral jsonb_array_elements(s.before_services) o
      where s.booking_id = b.id
        and not exists (select 1 from jsonb_array_elements(s.after_services) a where a->>'code' = o->>'code')
      union all
      select ev.created_at, 4, ev.id, ev.actor_id,
        case when ev.kind in ('booking_submitted', 'walk_in_submitted', 'booking_created_by_staff') then 'booked'
          when ev.kind in ('booking_confirmed', 'walk_in_confirmed') then 'approved'
          when ev.kind = 'completed' then 'completed'
          when ev.kind in ('booking_cancel_approved', 'booking_cancelled_by_staff') then 'cancelled'
          else 'rescheduled' end,
        null::text, null::text, null::bigint, null::bigint, null::text
      from public.herco_booking_events ev where ev.booking_id = b.id
        and ev.kind in ('booking_submitted', 'walk_in_submitted', 'booking_created_by_staff', 'booking_confirmed', 'walk_in_confirmed',
          'completed', 'booking_cancel_approved', 'booking_cancelled_by_staff', 'booking_reschedule_approved', 'booking_rescheduled_by_staff')
    ) r
    left join herco_private.staff_memberships sm on sm.user_id = r.actor_id
    left join public.herco_customer_profiles cp on cp.user_id = r.actor_id
    order by r.happened desc, r.src desc, r.seq desc limit 200
  ) top;
  return jsonb_build_object('booking_id', b.id, 'canViewIncome', show_money, 'entries', result);
end;
$$;

-- Reports search. Matches the booking id, reference, bike, customer name, phone, email and plate, plus the LABELS of the
-- current and original services (never the raw JSON, so keys like "code" or "label" and amounts cannot be found).
-- A phone also matches when the search has spaces or dashes the stored number does not, and the other way round.
-- needle must already be lower case and trimmed.
create function herco_private.booking_matches_search(b public.herco_bookings, needle text)
returns boolean language sql stable set search_path='' as $$
  select needle='' or position(needle in lower(concat_ws(' ',b.id::text,'HG-'||b.reference_no::text,b.bike,
      b.customer_contact->>'name',b.customer_contact->>'phone',b.customer_contact->>'email',b.customer_contact->>'plate',
      (select string_agg(l->>'label',' ') from jsonb_array_elements(coalesce(b.current_services,b.original_services)) l),
      (select string_agg(l->>'label',' ') from jsonb_array_elements(b.original_services) l))))>0
    or (regexp_replace(needle,'[\s-]','','g')<>''
      and position(regexp_replace(needle,'[\s-]','','g') in regexp_replace(coalesce(b.customer_contact->>'phone',''),'[\s-]','','g'))>0);
$$;
revoke all on function herco_private.booking_matches_search(public.herco_bookings,text) from public,anon,authenticated;

-- Reports records: adds sort "date_asc" (oldest first) and "price_asc" (low to high, no price last).
-- Same as 202611230003 except: the two new sorts; a booking's price is its current total (edited prices count);
-- the search uses herco_private.booking_matches_search (no amounts, so staff without viewIncome cannot find prices).
create or replace function public.herco_staff_booking_records(from_date date,through_date date,search_term text default '',status_filter text default 'all',source_filter text default 'all',record_page integer default 1,report_mode boolean default false,sort_by text default 'date')
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare member herco_private.staff_memberships; items jsonb; metrics jsonb; total integer; show_income boolean; applied_sort text;
  needle text:=lower(btrim(coalesce(search_term,'')));
begin
  if not herco_private.has_verified_staff_session() then raise exception 'Staff access required.' using errcode='42501'; end if;
  select * into member from herco_private.staff_memberships m where m.user_id=auth.uid() and m.enabled;
  if not (case when report_mode then 'Reports'=any(member.page_grants) else member.page_grants && array['Booking history','Bookings'] end) then
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

-- Owner decision 2026-11-24: once staff changed any line price of a booking, the customer can no longer edit its services.
-- True when a staff price change exists for the booking.
create function herco_private.is_shop_priced(booking uuid)
returns boolean language sql volatile set search_path = '' as $$
  select exists (select 1 from herco_private.booking_price_edits e where e.booking_id = booking);
$$;
revoke all on function herco_private.is_shop_priced(uuid) from public, anon, authenticated;

-- For My Bookings: which of the caller's own bookings were priced by the shop. Other people's ids are ignored.
create function public.herco_shop_priced_bookings(booking_ids uuid[])
returns uuid[] language plpgsql volatile security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'Sign in to see your bookings.' using errcode = '42501'; end if;
  if booking_ids is null or cardinality(booking_ids) > 100 then
    raise exception 'Choose up to 100 bookings.' using errcode = '22023';
  end if;
  return coalesce((select array_agg(b.id) from public.herco_bookings b
    where b.id = any(booking_ids) and b.customer_id = auth.uid() and herco_private.is_shop_priced(b.id)), '{}'::uuid[]);
end;
$$;

-- Same as 202611190033 plus: `shop_priced`, `canEdit` false for the customer once the shop priced the booking, and no
-- amounts (totalCentavos null, lines without money) when the caller is staff without viewIncome. Customers keep their own prices.
create or replace function public.herco_booked_services(booking_id uuid)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare result jsonb; booking public.herco_bookings; priced boolean; hide_money boolean;
begin
  result:=public.herco_booked_services_legacy(booking_id);
  select b.* into strict booking from public.herco_bookings b where b.id=booking_id;
  priced:=herco_private.is_shop_priced(booking.id);
  hide_money:=booking.customer_id is distinct from auth.uid() and not exists (select 1 from herco_private.staff_memberships m
    where m.user_id=auth.uid() and m.enabled and 'viewIncome'=any(m.action_grants));
  result:=result||jsonb_build_object('bike',booking.bike,'options',coalesce(booking.current_coating_options,booking.coating_options),
    'shop_priced',priced);
  if priced and booking.customer_id is not distinct from auth.uid() then result:=result||jsonb_build_object('canEdit',false); end if;
  if hide_money then
    result:=result||jsonb_build_object('original',herco_private.strip_service_money(result->'original'),
      'current',herco_private.strip_service_money(result->'current'),'totalCentavos',null::bigint,
      'changes',coalesce((select jsonb_agg(c||jsonb_build_object('before_services',herco_private.strip_service_money(c->'before_services'),
        'after_services',herco_private.strip_service_money(c->'after_services')) order by n)
        from jsonb_array_elements(result->'changes') with ordinality t(c,n)),'[]'::jsonb));
  end if;
  return result;
end $$;

-- Same as 202611190013 plus: a customer is refused (P0423) once the shop priced the booking; a staff add/remove keeps
-- every existing line (and its price), and a sum of lines without any price no longer fails.
create or replace function public.herco_save_booked_services(
  booking_id uuid, request_id uuid, expected_revision integer, service_codes text[]
)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  booking public.herco_bookings;
  previous herco_private.booking_service_changes;
  selected text[];
  editable boolean;
  old_lines jsonb;
  new_lines jsonb;
  total bigint;
  changed_at timestamptz := clock_timestamp();
begin
  if booking_id is null or request_id is null or expected_revision is null or expected_revision < 0
    or coalesce(cardinality(service_codes), 0) not between 1 and 20
    or array_position(service_codes, null) is not null then
    raise exception 'Choose between one and twenty services.' using errcode = '22023';
  end if;
  select array_agg(distinct code order by code) into selected from unnest(service_codes) as code;
  if cardinality(selected) <> cardinality(service_codes) then
    raise exception 'Choose each service once.' using errcode = '22023';
  end if;
  select b.* into booking from public.herco_bookings b where b.id = booking_id for update;
  if not found then raise exception 'Booking not found.' using errcode = 'P0002'; end if;
  editable := herco_private.may_edit_booked_services(booking);
  select c.* into previous from herco_private.booking_service_changes c where c.booking_id = booking.id
    and c.actor_id = auth.uid() and c.request_id = herco_save_booked_services.request_id;
  if found then
    if selected is distinct from previous.service_codes or expected_revision <> previous.revision - 1 then
      raise exception 'This request ID belongs to another service selection.' using errcode = '22023';
    end if;
    return public.herco_booked_services(booking.id);
  end if;
  if booking.customer_id is not distinct from auth.uid() and herco_private.is_shop_priced(booking.id) then
    raise exception 'The shop updated this booking after inspection. Contact the shop to change services.' using errcode = 'P0423';
  end if;
  if not editable or booking.service_revision <> expected_revision then
    raise exception 'The booking changed or is no longer editable. Reload before retrying.' using errcode = '40001';
  end if;

  old_lines := coalesce(booking.current_services, booking.original_services);
  select jsonb_agg(line.snapshot order by choice.code),
    sum(coalesce((line.snapshot->>'price_centavos')::bigint, 0))
  into new_lines, total
  from unnest(selected) choice(code)
  cross join lateral (
    select item as snapshot from jsonb_array_elements(old_lines) item where item->>'code' = choice.code
    union all
    select jsonb_strip_nulls(jsonb_build_object('code', c.code, 'label', c.label,
      'price_centavos', c.price_centavos, 'promotion', c.promotion,
      'max_centavos', c.max_centavos, 'quote_required', case when c.quote_required then true end)) from public.herco_catalog() c
    where c.code = choice.code and extract(dow from booking.visit_date)::smallint = any(c.appointment_days)
      and not exists (select 1 from jsonb_array_elements(old_lines) item where item->>'code' = choice.code)
  ) line;
  if new_lines is null or jsonb_array_length(new_lines) <> cardinality(selected) or total is null then
    raise exception 'A selected service is unavailable on the booked date.' using errcode = '22023';
  end if;
  if new_lines = old_lines then return public.herco_booked_services(booking.id); end if;
  update public.herco_bookings b set current_services = new_lines,
    current_total_centavos = total, service_revision = b.service_revision + 1 where b.id = booking.id;
  insert into herco_private.booking_service_changes (
    booking_id, actor_id, request_id, revision, service_codes, before_services, after_services, recorded_at
  ) values (booking.id, auth.uid(), request_id, expected_revision + 1, selected, old_lines, new_lines, changed_at);
  insert into public.herco_booking_events (booking_id, actor_id, kind, to_status)
    values (booking.id, auth.uid(), 'booking_services_updated', booking.status);
  return public.herco_booked_services(booking.id);
end
$$;

-- Same as 202611190033 plus: refused (P0423) once the shop priced the booking. This path rebuilds every line from the
-- catalog, so it would wipe the shop's prices; for staff the message points to Add service / remove (the plain function above).
create or replace function public.herco_save_booked_services_configured(booking_id uuid,request_id uuid,expected_revision integer,service_codes text[],options jsonb,expected_price_fingerprint text default null)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare booking public.herco_bookings;previous herco_private.booking_service_changes;normalized jsonb;selected text[];old_lines jsonb;new_lines jsonb;old_options jsonb;editable boolean;
begin
 if request_id is null or expected_revision is null or expected_revision<0 or coalesce(cardinality(service_codes),0) not between 1 and 20 or array_position(service_codes,null) is not null then raise exception 'Choose valid services.' using errcode='22023';end if;
 select b.* into booking from public.herco_bookings b where b.id=booking_id for update;
 if not found then raise exception 'Booking not found.' using errcode='P0002';end if;
 editable:=herco_private.may_edit_booked_services(booking);
 normalized:=herco_private.normalize_coating_options(options,service_codes,booking.bike);
 select array_agg(distinct code order by code) into selected from unnest(service_codes)code;
 if cardinality(selected)<>cardinality(service_codes) then raise exception 'Choose each service once.' using errcode='22023';end if;
 select c.* into previous from herco_private.booking_service_changes c where c.booking_id=booking.id and c.actor_id=auth.uid() and c.request_id=herco_save_booked_services_configured.request_id;
 if found then
  if previous.service_codes is distinct from selected or previous.after_options is distinct from normalized or previous.revision-1<>expected_revision then raise exception 'This request belongs to another edit.' using errcode='22023';end if;
  return public.herco_booked_services(booking.id);
 end if;
 if herco_private.is_shop_priced(booking.id) then
  if booking.customer_id is not distinct from auth.uid() then
   raise exception 'The shop updated this booking after inspection. Contact the shop to change services.' using errcode='P0423';
  end if;
  raise exception 'The shop changed prices on this booking. Add or remove services one by one so the prices are kept.' using errcode='P0423';
 end if;
 if not editable or booking.service_revision<>expected_revision then raise exception 'The booking changed or cannot be edited. Reload before retrying.' using errcode='40001';end if;
 old_lines:=coalesce(booking.current_services,booking.original_services);old_options:=coalesce(booking.current_coating_options,booking.coating_options);
 select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('code',c.code,'label',c.label,'price_centavos',c.price_centavos,'max_centavos',c.max_centavos,'quote_required',case when c.quote_required then true end,'promotion',c.promotion)) order by c.code) into new_lines from public.herco_catalog() c where c.code=any(selected) and extract(dow from booking.visit_date)::smallint=any(c.appointment_days);
 if coalesce(jsonb_array_length(new_lines),0)<>cardinality(selected) then raise exception 'A selected service is unavailable on the booked date.' using errcode='22023';end if;
 new_lines:=herco_private.coating_price_lines(new_lines,booking.bike,normalized);
 perform herco_private.require_unchanged_preview(new_lines,expected_price_fingerprint);
 if new_lines=old_lines and normalized=old_options then return public.herco_booked_services(booking.id);end if;
 update public.herco_bookings b set current_services=new_lines,current_total_centavos=herco_private.price_line_total(new_lines),current_coating_options=normalized,service_revision=b.service_revision+1 where b.id=booking.id;
 insert into herco_private.booking_service_changes(booking_id,actor_id,request_id,revision,service_codes,before_services,after_services,before_options,after_options)values(booking.id,auth.uid(),request_id,expected_revision+1,selected,old_lines,new_lines,old_options,normalized);
 insert into public.herco_booking_events(booking_id,actor_id,kind,to_status)values(booking.id,auth.uid(),'booking_services_updated',booking.status);
 return public.herco_booked_services(booking.id);
end $$;

revoke all on function public.herco_staff_set_line_price(uuid, uuid, text, bigint, bigint, text),
  public.herco_booking_history(uuid), public.herco_shop_priced_bookings(uuid[]), public.herco_booked_services(uuid),
  public.herco_save_booked_services(uuid, uuid, integer, text[]),
  public.herco_save_booked_services_configured(uuid, uuid, integer, text[], jsonb, text) from public, anon, authenticated;
grant execute on function public.herco_staff_set_line_price(uuid, uuid, text, bigint, bigint, text),
  public.herco_booking_history(uuid), public.herco_shop_priced_bookings(uuid[]), public.herco_booked_services(uuid),
  public.herco_save_booked_services(uuid, uuid, integer, text[]),
  public.herco_save_booked_services_configured(uuid, uuid, integer, text[], jsonb, text) to authenticated;

notify pgrst, 'reload schema';
commit;
