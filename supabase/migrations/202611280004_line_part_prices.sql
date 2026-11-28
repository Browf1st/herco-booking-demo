-- Owner decision 2026-11-28: staff edit each PART of a service (the base plus each option, e.g. Powder Coating
-- plus "Matte to Glossy"), not just one line total. This adds a 7-argument overload of herco_staff_set_line_price
-- that takes `parts` (the new per-component prices, in the order the line's details are shown). When `parts` is null
-- it behaves exactly like the original 6-argument function (one flat price, details dropped).
--  * A line that already has `details` keeps them, with the new per-part prices; its price is the sum of the parts.
--  * A line with no details is one component (its base); editing it stays a flat price, as before.
-- The original 6-argument function is untouched. The change is still recorded in herco_private.booking_price_edits
-- (line total from→to, with the whole previous line kept in previous_line, so the per-part diff is recoverable).
create function public.herco_staff_set_line_price(booking uuid, request_id uuid, service_code text,
  expected_price_centavos bigint, new_price_centavos bigint, reason text, parts jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  b public.herco_bookings;
  earlier herco_private.booking_price_edits;
  lines jsonb;
  line jsonb;
  revised jsonb;
  new_line jsonb;
  old_parts jsonb;
  new_details jsonb;
  old_price bigint;
  quote_line boolean;
  has_details boolean;
  parts_total bigint;
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
  -- Validate parts (when given): an array of 1..20 whole-peso prices that sum to new_price_centavos.
  if parts is not null then
    if jsonb_typeof(parts) <> 'array' or jsonb_array_length(parts) not between 1 and 20 then
      raise exception 'Enter a whole-peso price for each part.' using errcode = '22023';
    end if;
    if exists (select 1 from jsonb_array_elements(parts) p
      where jsonb_typeof(p->'price_centavos') <> 'number' or (p->>'price_centavos') !~ '^[0-9]{1,9}$'
        or (p->>'price_centavos')::bigint > 100000000 or (p->>'price_centavos')::bigint % 100 <> 0) then
      raise exception 'Enter a whole-peso price from 0 to 1,000,000 for each part.' using errcode = '22023';
    end if;
    select coalesce(sum((p->>'price_centavos')::bigint), 0) into parts_total from jsonb_array_elements(parts) p;
    if parts_total <> new_price_centavos then
      raise exception 'The parts do not add up to the new price.' using errcode = '22023';
    end if;
  end if;

  select x.* into b from public.herco_bookings x where x.id = booking for update;
  if not found then raise exception 'Booking not found.' using errcode = 'P0002'; end if;

  -- A repeated request (same staff member and request id) is answered from the saved change.
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
  if line is null then raise exception 'This service changed. Reload and try again.' using errcode = 'P0412'; end if;
  old_price := coalesce((line->>'price_centavos')::bigint, 0);
  quote_line := coalesce((line->>'quote_required')::boolean, false) or not (line ? 'price_centavos');
  has_details := (line ? 'details') and jsonb_typeof(line->'details') = 'array' and jsonb_array_length(line->'details') > 0;
  if old_price <> coalesce(expected_price_centavos, 0) then
    raise exception 'This service price changed. Reload and try again.' using errcode = 'P0412';
  end if;

  -- Build the new line. With parts, keep the per-part breakdown; without parts, it is one flat price (original behaviour).
  if parts is null then
    new_total := new_price_centavos;
    new_line := (line - 'max_centavos' - 'quote_required' - 'details' - 'promotion') || jsonb_build_object('price_centavos', new_total);
  else
    -- The number of parts must match what the staff member saw (their details, or the single base line).
    old_parts := case when has_details then line->'details'
      else jsonb_build_array(jsonb_build_object('label', coalesce(line->>'label', service_code), 'price_centavos', old_price)) end;
    if jsonb_array_length(parts) <> jsonb_array_length(old_parts) then
      raise exception 'This service changed. Reload and try again.' using errcode = 'P0412';
    end if;
    -- Keep each part's existing label, take the new price by position.
    select jsonb_agg(jsonb_build_object('label', op->>'label', 'price_centavos', (np->>'price_centavos')::bigint) order by n)
      into new_details
      from jsonb_array_elements(old_parts) with ordinality o(op, n)
      join jsonb_array_elements(parts) with ordinality p(np, m) on m = n;
    new_total := parts_total;
    new_line := (line - 'max_centavos' - 'quote_required' - 'details' - 'promotion') || jsonb_build_object('price_centavos', new_total)
      || case when has_details then jsonb_build_object('details', new_details) else '{}'::jsonb end;
  end if;

  if old_price = new_total and not quote_line and (parts is null or line->'details' is not distinct from new_details) then
    raise exception 'That is already the price.' using errcode = 'P0400';
  end if;

  select jsonb_agg(case when item->>'code' = service_code then new_line else item end order by pos)
    into revised from jsonb_array_elements(lines) with ordinality as l(item, pos);

  update public.herco_bookings set current_services = revised, current_total_centavos = new_total,
    service_revision = b.service_revision + 1 where id = b.id;
  insert into herco_private.booking_price_edits (booking_id, revision, actor_id, request_id, service_code, service_label,
    previous_centavos, new_centavos, reason, previous_line)
    values (b.id, b.service_revision + 1, auth.uid(), request_id, service_code, coalesce(line->>'label', service_code),
      case when quote_line then null else old_price end, new_total, note, line);
  insert into public.herco_booking_events (booking_id, actor_id, kind, to_status)
    values (b.id, auth.uid(), 'booking_line_price_changed', b.status);
  return jsonb_build_object('revision', b.service_revision + 1, 'status', b.status, 'lines', revised, 'totalCentavos', new_total);
end;
$$;
revoke all on function public.herco_staff_set_line_price(uuid, uuid, text, bigint, bigint, text, jsonb) from public, anon, authenticated;
grant execute on function public.herco_staff_set_line_price(uuid, uuid, text, bigint, bigint, text, jsonb) to authenticated;
