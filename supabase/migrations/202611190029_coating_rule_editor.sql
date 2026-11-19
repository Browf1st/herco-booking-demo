begin;

alter table herco_private.coating_price_rules
  add column revision integer not null default 1 check (revision > 0);
alter table herco_private.pricing_audit drop constraint pricing_audit_setting_check,
  add check (setting in ('service', 'promotion', 'coating_rule'));

create function public.herco_coating_rules()
returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare grants text[] := herco_private.pricing_grants();
begin
  return jsonb_build_object(
    'canEdit', ('changePricing' = any (grants)) is true,
    'rules', coalesce((select jsonb_agg(to_jsonb(r) order by r.service_code, r.bike_key, r.id)
      from herco_private.coating_price_rules r), '[]'::jsonb)
  );
end
$$;

create function public.herco_save_coating_rule(
  request_id uuid, rule_id uuid, expected_revision integer, service text, bike text, options jsonb,
  minimum_centavos integer, maximum_centavos integer, quote_required boolean, is_enabled boolean
)
returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  grants text[] := herco_private.pricing_grants();
  canonical_bike text := lower(btrim(coalesce(bike, '')));
  match_options jsonb;
  payload jsonb;
  replay jsonb;
  original herco_private.coating_price_rules;
  saved herco_private.coating_price_rules;
begin
  if ('changePricing' = any (grants)) is not true then
    raise exception 'You do not have permission to change coating prices.' using errcode = '42501';
  end if;
  if request_id is null or expected_revision is null or expected_revision < 0
    or ((rule_id is null) is distinct from (expected_revision = 0))
    or service is null or service not in ('ceramic', 'wheel-colour') or char_length(canonical_bike) > 120
    or minimum_centavos is null or minimum_centavos < 0
    or (maximum_centavos is not null and maximum_centavos <= minimum_centavos)
    or quote_required is null or is_enabled is null
    or (quote_required and (minimum_centavos <> 0 or maximum_centavos is not null)) then
    raise exception 'Check the service, bike and price amounts for this rule.' using errcode = '22023';
  end if;

  -- A generic Enhance rule still matches only configurations already validated
  -- against an eligible red ADV or PCX when the customer books.
  match_options := herco_private.normalize_coating_options(options, array[service],
    case when canonical_bike = '' and options->>'ceramic_finish' = 'Enhance' then 'Honda ADV160'
      else canonical_bike end);
  if match_options = '{}'::jsonb then
    raise exception 'Choose at least one finish or part to match.' using errcode = '22023';
  end if;

  payload := jsonb_build_object('id', rule_id, 'revision', expected_revision, 'service_code', service,
    'bike_key', canonical_bike, 'option_match', match_options, 'minimum_centavos', minimum_centavos,
    'maximum_centavos', maximum_centavos, 'quote_required', quote_required, 'enabled', is_enabled);
  replay := herco_private.pricing_replay(request_id, 'coating_rule', payload);
  if replay is not null then return replay; end if;

  if rule_id is null then
    insert into herco_private.coating_price_rules (
      service_code, bike_key, option_match, minimum_centavos, maximum_centavos, quote_required, enabled
    ) values (service, canonical_bike, match_options, minimum_centavos, maximum_centavos, quote_required, is_enabled)
    returning * into saved;
  else
    select r.* into original from herco_private.coating_price_rules r where r.id = rule_id for update;
    if not found or original.revision is distinct from expected_revision then
      raise exception 'This coating rule changed. Reload pricing before editing again.' using errcode = '40001';
    end if;
    update herco_private.coating_price_rules r set service_code = service,
      bike_key = canonical_bike, option_match = match_options,
      minimum_centavos = herco_save_coating_rule.minimum_centavos,
      maximum_centavos = herco_save_coating_rule.maximum_centavos,
      quote_required = herco_save_coating_rule.quote_required,
      enabled = is_enabled, revision = r.revision + 1 where r.id = rule_id
    returning * into saved;
  end if;

  insert into herco_private.pricing_audit (actor_id, request_id, setting, input_value, before_value, after_value)
  values (auth.uid(), request_id, 'coating_rule', payload, case when rule_id is not null then to_jsonb(original) end, to_jsonb(saved));
  return to_jsonb(saved);
end
$$;

revoke all on function public.herco_coating_rules(),
  public.herco_save_coating_rule(uuid, uuid, integer, text, text, jsonb, integer, integer, boolean, boolean)
  from public, anon, authenticated;
grant execute on function public.herco_coating_rules(),
  public.herco_save_coating_rule(uuid, uuid, integer, text, text, jsonb, integer, integer, boolean, boolean)
  to authenticated;

commit;
