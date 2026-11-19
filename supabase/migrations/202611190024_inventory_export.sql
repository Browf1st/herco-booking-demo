begin;

create function public.herco_inventory_export(export_kind text, from_date date default null, through_date date default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare starts timestamptz;
  ends timestamptz;
  rows jsonb;
begin
  perform herco_private.check_inventory_staff(false);
  if export_kind = 'stock' then
    select coalesce(jsonb_agg(to_jsonb(s)), '[]') into rows from
      (select name, category, unit, quantity, minimum, supplier, storage_location, unit_cost, billing_rate, capacity
       from herco_private.stock_items order by name,id limit 10001) s;
  elsif export_kind = 'movements' then
    if from_date is null or through_date is null or not isfinite(from_date) or not isfinite(through_date)
      or through_date < from_date or through_date-from_date > 365 then
      raise exception 'Choose a date range of up to 366 days.' using errcode = '22023';
    end if;
    starts := from_date::timestamp at time zone 'Asia/Manila';
    ends := (through_date+1)::timestamp at time zone 'Asia/Manila';
    select coalesce(jsonb_agg(to_jsonb(m)), '[]') into rows from (
      select a.recorded_at at time zone 'Asia/Manila' as recorded_at_ph,
        a.after_value->>'name' as name, a.after_value->>'unit' as unit, a.operation,
        (a.before_value->>'quantity')::numeric as before_quantity, (a.after_value->>'quantity')::numeric as after_quantity,
        a.input->>'reason' as reason, a.actor_id
      from herco_private.stock_activity a where a.recorded_at >= starts and a.recorded_at < ends
      order by a.recorded_at,a.request_id,a.actor_id limit 10001
    ) m;
  else raise exception 'Choose a valid export.' using errcode = '22023';
  end if;
  if jsonb_array_length(rows) > 10000 then
    raise exception 'Export contains more than 10,000 rows. Use a smaller date range for movements.' using errcode = '22023';
  end if;
  return rows;
end;
$$;

revoke all on function public.herco_inventory_export(text,date,date) from public, anon, authenticated;
grant execute on function public.herco_inventory_export(text,date,date) to authenticated;

commit;
