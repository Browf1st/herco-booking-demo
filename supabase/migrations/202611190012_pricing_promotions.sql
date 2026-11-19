begin;

alter table herco_private.services
  add column revision integer not null default 1 check (revision >= 1),
  add column max_centavos integer check (max_centavos > price_centavos),
  add column quote_required boolean not null default false,
  add check (not quote_required or (price_centavos = 0 and max_centavos is null));

create table herco_private.booking_promotion (
  singleton boolean primary key default true check (singleton),
  code text not null check (code ~ '^[a-z0-9][a-z0-9-]{0,63}$'),
  label text not null check (char_length(label) between 1 and 120),
  discount_basis_points integer not null check (discount_basis_points between 0 and 10000),
  enabled boolean not null default false,
  revision integer not null default 1 check (revision >= 1),
  check (not enabled or discount_basis_points > 0)
);

insert into herco_private.booking_promotion (code, label, discount_basis_points)
values ('booking-discount', 'Booking promotion', 0);

create table herco_private.pricing_audit (
  actor_id uuid not null references auth.users(id),
  request_id uuid not null,
  setting text not null check (setting in ('service', 'promotion')),
  input_value jsonb not null,
  before_value jsonb,
  after_value jsonb not null,
  recorded_at timestamptz not null default now(),
  primary key (actor_id, request_id)
);

alter table herco_private.booking_promotion enable row level security;
alter table herco_private.pricing_audit enable row level security;
revoke all on herco_private.booking_promotion, herco_private.pricing_audit from public, anon, authenticated;

create function herco_private.pricing_grants()
returns text[]
language plpgsql volatile set search_path = '' as $$
declare grants text[];
begin
  if auth.uid() is null or (auth.jwt()->>'aal') is distinct from 'aal2' then
    raise exception 'Verify your staff session first.' using errcode = '42501';
  end if;
  select m.action_grants into grants
  from herco_private.staff_memberships as m
  where m.user_id = auth.uid() and m.enabled and 'Pricing' = any (m.page_grants)
  for share;
  if not found then
    raise exception 'You do not have access to pricing.' using errcode = '42501';
  end if;
  return grants;
end;
$$;

create function herco_private.pricing_replay(request_id uuid, setting text, normalized jsonb)
returns jsonb
language plpgsql volatile set search_path = '' as $$
declare entry herco_private.pricing_audit;
begin
  perform pg_advisory_xact_lock(72120, hashtext(auth.uid()::text || ':' || request_id::text));
  select a.* into entry
  from herco_private.pricing_audit as a
  where a.actor_id = auth.uid() and a.request_id = pricing_replay.request_id;
  if not found then return null; end if;
  if entry.setting <> pricing_replay.setting or entry.input_value <> normalized then
    raise exception 'This request ID belongs to another pricing update.' using errcode = '22023';
  end if;
  return entry.after_value;
end;
$$;

create function public.herco_pricing()
returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare grants text[] := herco_private.pricing_grants();
begin
  return jsonb_build_object(
    'canEditServices', 'changePricing' = any (grants),
    'canEditPromotion', 'changePromotions' = any (grants),
    'services', coalesce((select jsonb_agg(to_jsonb(s) order by s.label, s.code)
      from herco_private.services as s), '[]'::jsonb),
    'promotion', (select to_jsonb(p) - 'singleton' from herco_private.booking_promotion as p)
  );
end;
$$;

create function public.herco_save_catalog_service(
  request_id uuid, service_code text, expected_revision integer, service_label text,
  base_price_centavos integer, is_enabled boolean, visit_days smallint[],
  maximum_centavos integer default null, needs_quote boolean default false
)
returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  grants text[] := herco_private.pricing_grants();
  clean_label text := btrim(coalesce(service_label, ''));
  days smallint[];
  original herco_private.services;
  updated herco_private.services;
  normalized jsonb;
  replay jsonb;
begin
  if not ('changePricing' = any (grants)) then
    raise exception 'You do not have permission to edit service prices.' using errcode = '42501';
  end if;
  if request_id is null or expected_revision is null or expected_revision < 0
    or service_code is null or service_code !~ '^[a-z0-9][a-z0-9-]{0,63}$'
    or char_length(clean_label) not between 1 and 120
    or base_price_centavos is null or base_price_centavos < 0
    or is_enabled is null or needs_quote is null
    or (needs_quote and (base_price_centavos <> 0 or maximum_centavos is not null))
    or (is_enabled and not needs_quote and base_price_centavos = 0)
    or (maximum_centavos is not null and maximum_centavos <= base_price_centavos)
    or coalesce(cardinality(visit_days), 0) not between 1 and 7
    or array_position(visit_days, null) is not null
    or not (visit_days <@ '{0,1,2,3,4,5,6}'::smallint[]) then
    raise exception 'Check the service price, label, appointment days and availability.' using errcode = '22023';
  end if;

  select array_agg(distinct n order by n) into days from unnest(visit_days) as n;
  normalized := jsonb_build_object('code', service_code, 'revision', expected_revision,
    'label', clean_label, 'price_centavos', base_price_centavos, 'enabled', is_enabled, 'appointment_days', days,
    'max_centavos', maximum_centavos, 'quote_required', needs_quote);
  replay := herco_private.pricing_replay(request_id, 'service', normalized);
  if replay is not null then return replay; end if;

  select s.* into original from herco_private.services as s where s.code = service_code for update;
  if not found then
    if expected_revision <> 0 then
      raise exception 'Reload pricing before editing again.' using errcode = '40001';
    end if;
    insert into herco_private.services (code, label, price_centavos, enabled, appointment_days, max_centavos, quote_required)
    values (service_code, clean_label, base_price_centavos, is_enabled, days, maximum_centavos, needs_quote)
    returning * into updated;
  else
    if original.revision <> expected_revision then
      raise exception 'Reload pricing before editing again.' using errcode = '40001';
    end if;
    update herco_private.services as s
    set label = clean_label,
      price_centavos = base_price_centavos, enabled = is_enabled, appointment_days = days,
      max_centavos = maximum_centavos, quote_required = needs_quote,
      revision = s.revision + 1
    where s.code = service_code
    returning s.* into updated;
  end if;

  insert into herco_private.pricing_audit (actor_id, request_id, setting, input_value, before_value, after_value)
  values (auth.uid(), request_id, 'service', normalized, to_jsonb(original), to_jsonb(updated));
  return to_jsonb(updated);
end;
$$;

create function public.herco_save_booking_promotion(
  request_id uuid, expected_revision integer, promotion_code text, display_label text,
  discount_bps integer, is_enabled boolean
)
returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  grants text[] := herco_private.pricing_grants();
  clean_label text := btrim(coalesce(display_label, ''));
  original herco_private.booking_promotion;
  updated herco_private.booking_promotion;
  normalized jsonb;
  replay jsonb;
begin
  if not ('changePromotions' = any (grants)) then
    raise exception 'You do not have permission to edit promotions.' using errcode = '42501';
  end if;
  if request_id is null or expected_revision is null or expected_revision < 1
    or promotion_code is null or promotion_code !~ '^[a-z0-9][a-z0-9-]{0,63}$'
    or char_length(clean_label) not between 1 and 120 or is_enabled is null
    or discount_bps is null or discount_bps not between 0 and 10000 or (is_enabled and discount_bps = 0) then
    raise exception 'Check the promotion code, label and discount.' using errcode = '22023';
  end if;

  normalized := jsonb_build_object('code', promotion_code, 'revision', expected_revision,
    'label', clean_label, 'discount_basis_points', discount_bps, 'enabled', is_enabled);
  replay := herco_private.pricing_replay(request_id, 'promotion', normalized);
  if replay is not null then return replay; end if;

  select p.* into original from herco_private.booking_promotion as p where p.singleton for update;
  if original.revision is distinct from expected_revision then
    raise exception 'Reload pricing before editing again.' using errcode = '40001';
  end if;
  update herco_private.booking_promotion as p
  set code = promotion_code, label = clean_label,
    discount_basis_points = discount_bps, enabled = is_enabled, revision = p.revision + 1
  where p.singleton
  returning p.* into updated;

  insert into herco_private.pricing_audit (actor_id, request_id, setting, input_value, before_value, after_value)
  values (auth.uid(), request_id, 'promotion', normalized,
    to_jsonb(original) - 'singleton', to_jsonb(updated) - 'singleton');
  return to_jsonb(updated) - 'singleton';
end;
$$;

-- Round each line's discount to the nearest centavo. Both the catalog and booking snapshots use this calculation.
create function herco_private.pricing_discount(base_price integer, basis_points integer)
returns integer
language sql immutable set search_path = '' as $$
  select ((base_price::bigint * basis_points + 5000) / 10000)::integer;
$$;

create function herco_private.promotion_snapshot(
  promotion herco_private.booking_promotion, base_price integer, discount integer
)
returns jsonb
language sql immutable set search_path = '' as $$
  select case when discount > 0 then jsonb_build_object(
    'code', promotion.code, 'label', promotion.label, 'discount_basis_points', promotion.discount_basis_points,
    'base_price_centavos', base_price, 'discount_centavos', discount
  ) end;
$$;

drop function public.herco_catalog();
create function public.herco_catalog()
returns table (code text, label text, price_centavos integer, appointment_days smallint[], promotion jsonb,
  max_centavos integer, quote_required boolean)
language sql stable security definer set search_path = '' as $$
  select s.code, s.label, s.price_centavos - discount.value, s.appointment_days,
    herco_private.promotion_snapshot(p, s.price_centavos, discount.value),
    case when p.enabled then s.max_centavos-herco_private.pricing_discount(s.max_centavos,p.discount_basis_points)
      else s.max_centavos end, s.quote_required
  from herco_private.services as s
  cross join herco_private.booking_promotion as p
  cross join lateral (select case when p.enabled
    then herco_private.pricing_discount(s.price_centavos, p.discount_basis_points) else 0 end as value) as discount
  where s.enabled
  order by s.label, s.code;
$$;

-- All booking entry points insert their trusted base snapshots here. Updates never reprice a saved booking.
create function herco_private.snapshot_booking_promotion()
returns trigger
language plpgsql volatile set search_path = '' as $$
declare
  promotion herco_private.booking_promotion;
  services jsonb;
  total bigint;
begin
  select p.* into promotion from herco_private.booking_promotion as p where p.singleton and p.enabled;
  select jsonb_agg(item.line || jsonb_strip_nulls(jsonb_build_object(
      'price_centavos', price.value-discount.value,
      'promotion',herco_private.promotion_snapshot(promotion,price.value,discount.value),
      'max_centavos', s.max_centavos-herco_private.pricing_discount(s.max_centavos,coalesce(promotion.discount_basis_points,0)),
      'quote_required', case when s.quote_required then true end
    )) order by item.ordinality), sum(price.value-discount.value)
  into services, total
  from jsonb_array_elements(new.original_services) with ordinality as item(line, ordinality)
  left join herco_private.services s on s.code=item.line->>'code'
  cross join lateral (select (item.line->>'price_centavos')::integer as value) as price
  cross join lateral (select herco_private.pricing_discount(price.value,coalesce(promotion.discount_basis_points,0)) as value) as discount;

  if services is not null and total is not null then
    new.original_services := services;
    new.original_total_centavos := total;
  end if;
  return new;
end;
$$;

create trigger herco_snapshot_booking_promotion
before insert on public.herco_bookings
for each row execute function herco_private.snapshot_booking_promotion();

revoke all on function herco_private.pricing_grants(), herco_private.pricing_replay(uuid, text, jsonb),
  herco_private.pricing_discount(integer, integer),
  herco_private.promotion_snapshot(herco_private.booking_promotion, integer, integer),
  herco_private.snapshot_booking_promotion() from public, anon, authenticated;
revoke all on function public.herco_pricing(),
  public.herco_save_catalog_service(uuid, text, integer, text, integer, boolean, smallint[], integer, boolean),
  public.herco_save_booking_promotion(uuid, integer, text, text, integer, boolean),
  public.herco_catalog() from public, anon, authenticated;
grant execute on function public.herco_pricing(),
  public.herco_save_catalog_service(uuid, text, integer, text, integer, boolean, smallint[], integer, boolean),
  public.herco_save_booking_promotion(uuid, integer, text, text, integer, boolean) to authenticated;
grant execute on function public.herco_catalog() to anon, authenticated;

commit;
