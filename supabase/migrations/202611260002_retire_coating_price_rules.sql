-- F-021 step 2: retire the legacy coating price rules engine. Run only after 202611260001 and after the Worker
-- no longer calls /api/pricing/coating-rules (it reads/writes the functions dropped here).
-- Safe for history: saved bookings keep their own `original_services` / `current_services` JSON (no live join to the
-- table; only a `coating_rule_id` note inside old line JSON, which nothing reads). This file never writes bookings.
-- Before dropping, every rule row is copied (as JSON) into herco_private.coating_price_rules_archive, so nothing is lost.
-- BACKUP FIRST on a hosted project (the free plan has none): the table drop cannot be undone except from the archive.
begin;

create table if not exists herco_private.coating_price_rules_archive(
 id uuid primary key,
 rule jsonb not null,
 archived_at timestamptz not null default now()
);
alter table herco_private.coating_price_rules_archive enable row level security;
revoke all on herco_private.coating_price_rules_archive from public,anon,authenticated;

create function herco_private.retire_coating_price_rules_data()
returns void language plpgsql volatile set search_path='' as $$ begin
 if to_regclass('herco_private.coating_price_rules') is not null then
  -- 1. Archive every rule.
  execute $q$insert into herco_private.coating_price_rules_archive(id,rule) select r.id,to_jsonb(r) from herco_private.coating_price_rules r on conflict do nothing$q$;
  -- 2. Move still-wanted rules into powderModel.exceptions: enabled, powder (wheel-colour), bike-specific, naming a finish.
  --    Tagged note 'migrated:<rule id>' so a re-run adds nothing. Rules that cannot be expressed (ceramic, no bike, no finish)
  --    stay only in the archive.
  execute $q$
   update herco_private.ui_pricing p set revision=p.revision+1,
    config=jsonb_set(p.config,'{powderModel,exceptions}',coalesce(p.config->'powderModel'->'exceptions','[]'::jsonb)||m.items)
   from (select jsonb_agg(jsonb_build_object('id',gen_random_uuid()::text,'service','wheel-colour','bikeKey',s.bike_key,'finish',btrim(s.option_match->>'finish'),
     'enabled',true,'note','migrated:'||s.id)||case when s.quote_required then '{"quoteOnly":true}'::jsonb else jsonb_build_object('priceCentavos',s.minimum_centavos) end order by s.id) items
    from (select distinct on (r.bike_key,lower(btrim(r.option_match->>'finish'))) r.* from herco_private.coating_price_rules r
     where r.enabled and r.service_code='wheel-colour' and r.bike_key<>'' and jsonb_typeof(r.option_match->'finish')='string'
      and char_length(btrim(r.option_match->>'finish')) between 1 and 100
      and not exists(select 1 from herco_private.ui_pricing u,jsonb_array_elements(coalesce(u.config->'powderModel'->'exceptions','[]'::jsonb)) x
       where u.singleton and (x.value->>'note'='migrated:'||r.id or (x.value->>'bikeKey'=r.bike_key and lower(btrim(x.value->>'finish'))=lower(btrim(r.option_match->>'finish')) and x.value->>'fromFinish' is null)))
     order by r.bike_key,lower(btrim(r.option_match->>'finish')),r.id) s) m
   where p.singleton and jsonb_typeof(p.config->'powderModel')='object' and m.items is not null$q$;
 end if;
 if exists(select 1 from herco_private.ui_pricing where singleton and config ? 'powderModel' and not herco_private.valid_powder_model(config->'powderModel')) then
  raise exception 'Migrated exceptions made the powder model invalid.'; end if;
end $$;
revoke all on function herco_private.retire_coating_price_rules_data() from public,anon,authenticated;
-- Kept (private, no-op once the table is gone) so the data move stays testable.
select herco_private.retire_coating_price_rules_data();

-- 3. Stop the legacy path reading the table: legacy (non-ui_catalog) options now keep their catalog prices.
create or replace function herco_private.coating_price_lines_legacy(base_lines jsonb, bike text, options jsonb)
returns jsonb language plpgsql stable set search_path = '' as $$
begin
  return base_lines;
end;
$$;
revoke all on function herco_private.coating_price_lines_legacy(jsonb,text,jsonb) from public, anon, authenticated;

-- 4. Remove the editor functions, then the table.
drop function if exists public.herco_coating_rules();
drop function if exists public.herco_save_coating_rule(uuid, uuid, integer, text, text, jsonb, integer, integer, boolean, boolean);
drop table if exists herco_private.coating_price_rules;

notify pgrst,'reload schema';
commit;
