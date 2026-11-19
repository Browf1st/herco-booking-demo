begin;

create table herco_private.booking_price_corrections (
  booking_id uuid not null references public.herco_bookings(id),
  revision integer not null,
  actor_id uuid not null references auth.users(id),
  request_id uuid not null,
  service_code text not null,
  previous_centavos bigint,
  corrected_centavos bigint not null,
  previous_completed_centavos bigint,
  corrected_completed_centavos bigint,
  reason text not null,
  recorded_at timestamptz not null default now(),
  primary key (booking_id, revision),
  unique (booking_id, actor_id, request_id)
);
alter table herco_private.booking_price_corrections enable row level security;
revoke all on herco_private.booking_price_corrections from public, anon, authenticated;

create function herco_private.require_price_adjustment()
returns void language plpgsql volatile set search_path = '' as $$
begin
  if (auth.jwt()->>'aal') is distinct from 'aal2' then
    raise exception 'Price corrections require staff MFA.' using errcode = '42501';
  end if;
  perform 1 from herco_private.staff_memberships s where s.user_id = auth.uid() and s.enabled
    and s.page_grants && array['Bookings','Booking history'] and 'adjustPrices' = any(s.action_grants)
    for share;
  if not found then raise exception 'Price corrections require staff permission.' using errcode = '42501'; end if;
end;
$$;

create function public.herco_booking_prices(booking uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare result jsonb;
begin
  perform herco_private.require_price_adjustment();
  select jsonb_build_object('revision', b.service_revision, 'lines', coalesce(b.current_services,b.original_services),
    'status', b.status,
    'corrections', coalesce((select jsonb_agg(to_jsonb(recent) order by recent.revision desc) from (
      select c.revision, c.service_code, c.previous_centavos, c.corrected_centavos, c.reason, c.recorded_at
      from herco_private.booking_price_corrections c where c.booking_id=b.id order by c.revision desc limit 20
    ) recent), '[]'::jsonb)) into result from public.herco_bookings b where b.id=booking;
  if not found then raise exception 'Booking not found.' using errcode = 'P0002'; end if;
  return result;
end;
$$;

create function public.herco_correct_booking_price(booking uuid, expected_revision integer, request_id uuid,
  service_code text, price_centavos bigint, reason text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare b public.herco_bookings;
  earlier herco_private.booking_price_corrections;
  lines jsonb;
  revised jsonb;
  old_price bigint;
  old_report bigint;
  new_report bigint;
  completed_price bigint;
  note text := btrim(reason);
begin
  perform herco_private.require_price_adjustment();
  if booking is null or expected_revision is null or expected_revision < 0 or request_id is null
     or service_code is null or length(service_code) not between 1 and 100 or price_centavos is null
     or price_centavos not between 0 and 99999999999 or note is null or length(note) not between 1 and 300 then
    raise exception 'Enter an exact price and reason.' using errcode = '22023';
  end if;
  select * into b from public.herco_bookings where id=booking for update;
  if not found then raise exception 'Booking not found.' using errcode = 'P0002'; end if;
  select c.* into earlier from herco_private.booking_price_corrections c
    where c.booking_id=booking and c.actor_id=auth.uid() and c.request_id=herco_correct_booking_price.request_id;
  if found then
    if earlier.revision <> expected_revision + 1 or earlier.service_code <> service_code
      or earlier.corrected_centavos <> price_centavos or earlier.reason <> note then
      raise exception 'Request already used for a different correction.' using errcode = '22023';
    end if;
    return public.herco_booking_prices(booking);
  end if;
  if b.service_revision <> expected_revision then
    raise exception 'Booking prices changed. Reload before retrying.' using errcode = '40001';
  end if;
  lines := coalesce(b.current_services,b.original_services);
  select (i->>'price_centavos')::bigint into old_price from jsonb_array_elements(lines) i
    where i->>'code'=service_code;
  if not found then raise exception 'Service not found on this booking.' using errcode = '22023'; end if;
  select jsonb_agg(case when item->>'code'=service_code
    then (item - 'max_centavos' - 'quote_required') || jsonb_build_object('price_centavos',price_centavos)
    else item end order by pos) into revised from jsonb_array_elements(lines) with ordinality as l(item,pos);
  if b.status='done' then
    select c.final_price_centavos into completed_price from herco_private.booking_completion c where c.booking_id=booking;
    if not found then raise exception 'Historical completion has no recorded final price.' using errcode = '23514'; end if;
    select c.corrected_completed_centavos into old_report from herco_private.booking_price_corrections c
      where c.booking_id=booking and c.corrected_completed_centavos is not null order by c.revision desc limit 1;
    old_report := coalesce(old_report, completed_price);
    new_report := old_report - coalesce(old_price,0) + price_centavos;
    if new_report not between 0 and 99999999999 then
      raise exception 'The correction would put the completed value outside the allowed range.' using errcode = '23514';
    end if;
  end if;
  update public.herco_bookings set current_services=revised,
    current_total_centavos=(select coalesce(sum((i->>'price_centavos')::bigint),0) from jsonb_array_elements(revised) i),
    service_revision=expected_revision+1 where id=booking;
  insert into herco_private.booking_price_corrections (booking_id,revision,actor_id,request_id,service_code,
    previous_centavos,corrected_centavos,previous_completed_centavos,corrected_completed_centavos,reason)
    values (booking,expected_revision+1,auth.uid(),request_id,service_code,old_price,price_centavos,old_report,new_report,note);
  insert into public.herco_booking_events(booking_id,actor_id,kind,to_status)
    values (booking,auth.uid(),'booking_price_corrected',b.status);
  return public.herco_booking_prices(booking);
end;
$$;

create or replace function public.herco_booking_report(from_date date, to_date date)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare actions text[];
  include_value boolean;
begin
  if (auth.jwt()->>'aal') is distinct from 'aal2' then
    raise exception 'Reports require staff permission and MFA.' using errcode = '42501';
  end if;
  select s.action_grants into actions from herco_private.staff_memberships s
    where s.user_id = auth.uid() and s.enabled and 'Reports' = any(s.page_grants);
  if not found then raise exception 'This account cannot access reports.' using errcode = '42501'; end if;
  if from_date is null or to_date is null or to_date < from_date or to_date-from_date > 365 then
    raise exception 'Choose a date range of up to 366 days.' using errcode = '22023';
  end if;
  include_value := 'viewIncome' = any(actions);
  return (select jsonb_build_object('total',count(*),'pending',count(*) filter (where b.status='pending'),
    'booked',count(*) filter (where b.status='confirmed'),'cancelled',count(*) filter (where b.status='cancelled'),
    'completed',count(*) filter (where b.status='done'),
    'completedWithoutValue',case when include_value then count(*) filter (where b.status='done' and c.booking_id is null) end,
    'completedValueCentavos',case when include_value then coalesce(sum(coalesce(p.corrected_completed_centavos,c.final_price_centavos))
      filter (where b.status='done'),0) end,
    'valueCorrectionsCentavos',case when include_value then coalesce(sum(p.corrected_completed_centavos-c.final_price_centavos),0) end)
    from public.herco_bookings b left join herco_private.booking_completion c on c.booking_id=b.id
    left join lateral (select x.corrected_completed_centavos from herco_private.booking_price_corrections x
      where include_value and x.booking_id=b.id and x.corrected_completed_centavos is not null
      order by x.revision desc limit 1) p on true
    where b.visit_date between from_date and to_date);
end;
$$;

revoke all on function herco_private.require_price_adjustment(), public.herco_booking_prices(uuid),
  public.herco_correct_booking_price(uuid,integer,uuid,text,bigint,text) from public, anon, authenticated;
grant execute on function public.herco_booking_prices(uuid), public.herco_correct_booking_price(uuid,integer,uuid,text,bigint,text)
  to authenticated;

commit;
