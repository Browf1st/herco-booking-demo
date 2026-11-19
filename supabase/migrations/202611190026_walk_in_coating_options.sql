begin;

create function public.herco_create_walk_in_booking_configured(
  p_request_id uuid, p_date date, p_service_codes text[], p_bike text, p_name text, p_phone text,
  p_plate text, p_form_version text, p_signer_name text, p_acknowledged boolean, p_options jsonb default '{}'
)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  actor uuid := herco_private.walk_in_actor();
  normalized jsonb;
  previous_options jsonb;
  receipt jsonb;
  booking public.herco_bookings;
begin
  if p_request_id is null then raise exception 'Choose a booking request ID.' using errcode = '22023'; end if;
  normalized := herco_private.normalize_coating_options(p_options,p_service_codes,p_bike);
  perform pg_advisory_xact_lock(72001,hashtext(actor::text || ':' || p_request_id::text));
  select b.coating_options into previous_options from public.herco_bookings b
    where b.customer_id=actor and b.request_id=p_request_id;
  if previous_options is not null and previous_options is distinct from normalized then
    raise exception 'This request ID belongs to different coating details.' using errcode = '22023';
  end if;
  receipt := public.herco_create_walk_in_booking(p_request_id,p_date,p_service_codes,p_bike,p_name,p_phone,
    p_plate,p_form_version,p_signer_name,p_acknowledged);
  if previous_options is null and normalized <> '{}'::jsonb then
    booking := herco_private.apply_configured_coating_prices((receipt->>'id')::uuid,normalized);
    receipt := receipt || jsonb_build_object('totalCentavos',booking.original_total_centavos,
      'estimateOpen',exists (select 1 from jsonb_array_elements(booking.original_services) line
        where line->'quote_required'='true'::jsonb or jsonb_typeof(line->'max_centavos')='number'));
  end if;
  return receipt;
end;
$$;

revoke all on function public.herco_create_walk_in_booking_configured(uuid,date,text[],text,text,text,text,text,text,boolean,jsonb)
  from public, anon, authenticated;
grant execute on function public.herco_create_walk_in_booking_configured(uuid,date,text[],text,text,text,text,text,text,boolean,jsonb)
  to authenticated;

commit;
