begin;

-- An exact match per service, with an optional bike-specific override. No sample prices are enabled.
create table herco_private.coating_price_rules (
  id uuid primary key default gen_random_uuid(),
  service_code text not null references herco_private.services(code) check (service_code in ('ceramic','wheel-colour')),
  bike_key text not null default '' check (bike_key = lower(btrim(bike_key)) and length(bike_key) <= 120),
  option_match jsonb not null check (jsonb_typeof(option_match)='object' and option_match <> '{}'::jsonb),
  minimum_centavos integer not null check (minimum_centavos >= 0),
  maximum_centavos integer check (maximum_centavos > minimum_centavos),
  quote_required boolean not null default false,
  enabled boolean not null default false,
  check (not quote_required or (minimum_centavos=0 and maximum_centavos is null)),
  unique(service_code,bike_key,option_match)
);
alter table herco_private.coating_price_rules enable row level security;
revoke all on herco_private.coating_price_rules from public, anon, authenticated;

create function herco_private.apply_configured_coating_prices(booking_id uuid, options jsonb)
returns public.herco_bookings language plpgsql volatile set search_path = '' as $$
declare booking public.herco_bookings;
  rule herco_private.coating_price_rules;
  promo herco_private.booking_promotion;
  line jsonb;
  matched jsonb;
  code text;
  lines jsonb := '[]';
  discount integer;
  maximum integer;
begin
  select b.* into strict booking from public.herco_bookings b where b.id=booking_id for update;
  select p.* into promo from herco_private.booking_promotion p where p.singleton and p.enabled;
  for line in select value from jsonb_array_elements(booking.original_services) loop
    code := line->>'code';
    matched := case code
      when 'ceramic' then options - array['powder_parts','wheel_front','wheel_rear']
      when 'wheel-colour' then options - array['ceramic_finish','red_body']
      else '{}'::jsonb end;
    select r.* into rule from herco_private.coating_price_rules r
      where r.enabled and r.service_code=code and r.option_match=matched
        and r.bike_key in ('',lower(booking.bike))
      order by (r.bike_key <> '') desc limit 1;
    if found then
      discount := herco_private.pricing_discount(rule.minimum_centavos,coalesce(promo.discount_basis_points,0));
      maximum := rule.maximum_centavos-herco_private.pricing_discount(rule.maximum_centavos,coalesce(promo.discount_basis_points,0));
      line := (line - array['price_centavos','max_centavos','quote_required','promotion']) ||
        jsonb_strip_nulls(jsonb_build_object(
          'price_centavos',rule.minimum_centavos-discount,'max_centavos',maximum,
          'quote_required',case when rule.quote_required then true end,
          'promotion',herco_private.promotion_snapshot(promo,rule.minimum_centavos,discount),
          'coating_rule_id',rule.id
        ));
    end if;
    lines := lines || jsonb_build_array(line);
  end loop;
  update public.herco_bookings b set coating_options=options, original_services=lines,
      original_total_centavos=(select coalesce(sum((item->>'price_centavos')::bigint),0) from jsonb_array_elements(lines) item)
    where b.id=booking_id returning b.* into booking;
  return booking;
end;
$$;
revoke all on function herco_private.apply_configured_coating_prices(uuid,jsonb) from public, anon, authenticated;

commit;
