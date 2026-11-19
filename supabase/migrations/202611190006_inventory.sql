begin;

create table herco_private.stock_items (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(btrim(name)) between 1 and 120),
  unit text not null check (char_length(btrim(unit)) between 1 and 30),
  category text not null default '' check (char_length(category) <= 60),
  minimum numeric(12,3) not null check (minimum >= 0),
  quantity numeric(12,3) not null default 0 check (quantity >= 0),
  supplier text check (char_length(supplier) <= 120),
  storage_location text check (char_length(storage_location) <= 120),
  unit_cost numeric(12,2) check (unit_cost between 0 and 9999999999.99),
  billing_rate numeric(12,2) check (billing_rate between 0 and 9999999999.99),
  capacity numeric(12,3) check (capacity between 0 and 999999999.999),
  revision integer not null default 1 check (revision > 0)
);
create unique index stock_items_name_idx on herco_private.stock_items(lower(btrim(name)));

create table herco_private.stock_activity (
  actor_id uuid not null references auth.users(id),
  request_id uuid not null,
  stock_id uuid not null references herco_private.stock_items(id),
  operation text not null check (operation in ('create', 'edit', 'move')),
  input jsonb not null,
  before_value jsonb,
  after_value jsonb not null,
  recorded_at timestamptz not null default now(),
  primary key (actor_id, request_id)
);
create index stock_activity_recent on herco_private.stock_activity(recorded_at desc);
alter table herco_private.stock_items enable row level security;
alter table herco_private.stock_activity enable row level security;
revoke all on herco_private.stock_items, herco_private.stock_activity from public, anon, authenticated;

create function herco_private.check_inventory_staff(write_access boolean)
returns void language plpgsql stable set search_path = '' as $$
begin
  if (auth.jwt()->>'aal') is distinct from 'aal2' or not exists (
    select 1 from herco_private.staff_memberships s
    where s.user_id = auth.uid() and s.enabled and 'Inventory' = any(s.page_grants)
      and (not write_access or 'manageInventory' = any(s.action_grants))
  ) then
    raise exception 'Inventory access requires staff permission and MFA.' using errcode = '42501';
  end if;
end;
$$;
revoke all on function herco_private.check_inventory_staff(boolean) from public, anon, authenticated;

create function public.herco_inventory()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform herco_private.check_inventory_staff(false);
  return jsonb_build_object(
    'canManage', (select 'manageInventory' = any(s.action_grants) from herco_private.staff_memberships s where s.user_id = auth.uid()),
    'items', (select coalesce(jsonb_agg(to_jsonb(s) order by s.name, s.id), '[]'::jsonb) from herco_private.stock_items s),
    'recent', (select coalesce(jsonb_agg(to_jsonb(a) order by a.recorded_at desc, a.request_id), '[]'::jsonb)
      from (select recorded_at, request_id, stock_id, operation, actor_id, input, before_value, after_value
        from herco_private.stock_activity order by recorded_at desc, request_id limit 30) a)
  );
end;
$$;

create function public.herco_write_inventory(request_id uuid, operation text, stock_id uuid, details jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare prior herco_private.stock_activity;
  current_stock herco_private.stock_items;
  updated_stock herco_private.stock_items;
  snapshot jsonb;
  amount numeric;
  stock_name text;
  stock_unit text;
  stock_category text;
  stock_minimum numeric;
  stock_supplier text;
  stock_location text;
  stock_unit_cost numeric;
  stock_billing_rate numeric;
  stock_capacity numeric;
begin
  perform herco_private.check_inventory_staff(true);
  if request_id is null or stock_id is null or operation is null or operation not in ('create', 'edit', 'move')
    or details is null or jsonb_typeof(details) <> 'object' or pg_column_size(details) > 4096 then
    raise exception 'Check the inventory details.' using errcode = '22023';
  end if;
  perform pg_advisory_xact_lock(72005, hashtext(auth.uid()::text || ':' || request_id::text));
  select a.* into prior from herco_private.stock_activity a
    where a.actor_id = auth.uid() and a.request_id = herco_write_inventory.request_id;
  if found then
    if prior.input <> details or prior.stock_id <> stock_id or prior.operation <> operation then
      raise exception 'Request ID was already used.' using errcode = '22023';
    end if;
    return prior.after_value;
  end if;

  if operation in ('create', 'edit') then
    stock_name := btrim(details->>'name');
    stock_unit := btrim(details->>'unit');
    stock_category := btrim(coalesce(details->>'category', ''));
    stock_minimum := (details->>'minimum')::numeric;
    stock_supplier := nullif(btrim(details->>'supplier'), '');
    stock_location := nullif(btrim(details->>'storage_location'), '');
    stock_unit_cost := (details->>'unit_cost')::numeric;
    stock_billing_rate := (details->>'billing_rate')::numeric;
    stock_capacity := (details->>'capacity')::numeric;
    if stock_name is null or char_length(stock_name) not between 1 and 120 or
       stock_unit is null or char_length(stock_unit) not between 1 and 30 or char_length(stock_category) > 60 or
       stock_minimum is null or stock_minimum not between 0 and 999999999.999 or scale(stock_minimum) > 3 or
       char_length(stock_supplier) > 120 or char_length(stock_location) > 120 or
       stock_unit_cost not between 0 and 9999999999.99 or scale(stock_unit_cost) > 2 or
       stock_billing_rate not between 0 and 9999999999.99 or scale(stock_billing_rate) > 2 or
       stock_capacity not between 0 and 999999999.999 or scale(stock_capacity) > 3 then
      raise exception 'Enter item details and a valid minimum quantity.' using errcode = '22023';
    end if;
  end if;

  if operation = 'create' then
    amount := (details->>'quantity')::numeric;
    if amount is null or amount not between 0 and 999999999.999 or scale(amount) > 3 then
      raise exception 'Enter a valid opening quantity.' using errcode = '22023';
    end if;
    insert into herco_private.stock_items(id, name, unit, category, minimum, quantity,
      supplier, storage_location, unit_cost, billing_rate, capacity)
      values (stock_id, stock_name, stock_unit, stock_category, stock_minimum, amount,
        stock_supplier, stock_location, stock_unit_cost, stock_billing_rate, stock_capacity)
      returning * into updated_stock;
  else
    select i.* into current_stock from herco_private.stock_items i where i.id = stock_id for update;
    if not found then raise exception 'Inventory item not found.' using errcode = '22023'; end if;
    snapshot := to_jsonb(current_stock);
    if operation = 'edit' then
      if (details->>'revision')::integer is distinct from current_stock.revision then
        raise exception 'This item changed. Refresh before editing.' using errcode = '40001';
      end if;
      update herco_private.stock_items i set name = stock_name, unit = stock_unit, category = stock_category,
        minimum = stock_minimum,
        supplier = case when details ? 'supplier' then stock_supplier else i.supplier end,
        storage_location = case when details ? 'storage_location' then stock_location else i.storage_location end,
        unit_cost = case when details ? 'unit_cost' then stock_unit_cost else i.unit_cost end,
        billing_rate = case when details ? 'billing_rate' then stock_billing_rate else i.billing_rate end,
        capacity = case when details ? 'capacity' then stock_capacity else i.capacity end,
        revision = i.revision + 1 where i.id = stock_id returning * into updated_stock;
    else
      amount := (details->>'delta')::numeric;
      if amount is null or amount = 0 or amount not between -999999999.999 and 999999999.999
        or scale(amount) > 3 or nullif(btrim(details->>'reason'), '') is null
        or char_length(btrim(details->>'reason')) > 300 then
        raise exception 'Enter a stock change and reason.' using errcode = '22023';
      end if;
      if current_stock.quantity + amount not between 0 and 999999999.999 then
        raise exception 'The resulting quantity is outside the allowed range.' using errcode = '23514';
      end if;
      update herco_private.stock_items i set quantity = i.quantity + amount, revision = i.revision + 1
        where i.id = stock_id returning * into updated_stock;
    end if;
  end if;

  insert into herco_private.stock_activity(actor_id, request_id, stock_id, operation, input, before_value, after_value)
    values (auth.uid(), request_id, stock_id, operation, details, snapshot, to_jsonb(updated_stock));
  return to_jsonb(updated_stock);
end;
$$;

revoke all on function public.herco_inventory(), public.herco_write_inventory(uuid, text, uuid, jsonb)
  from public, anon, authenticated;
grant execute on function public.herco_inventory(), public.herco_write_inventory(uuid, text, uuid, jsonb)
  to authenticated;

commit;
