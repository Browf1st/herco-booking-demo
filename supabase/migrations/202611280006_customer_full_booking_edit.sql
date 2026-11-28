-- Customer edits a whole PENDING booking: motorcycle, services, add-ons and contact, re-priced on the server.
-- Mirrors public.herco_save_booked_services_configured (202611240001) plus new bike and contact. The original snapshot
-- (original_services, original_total_centavos, coating_options) is never changed. Email is never changed here.
begin;

-- Same as 202611240001 plus a `contact` object {name, phone, plate} (never the email). Access is gated by the legacy
-- function (may_edit_booked_services raises 42501 for anyone who is not the owner or allowed staff).
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
    'shop_priced',priced,
    'contact',jsonb_build_object('name',coalesce(booking.customer_contact->>'name',''),'phone',coalesce(booking.customer_contact->>'phone',''),
      'plate',coalesce(booking.customer_contact->>'plate','')));
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

create or replace function public.herco_edit_booking_configured(booking_id uuid,request_id uuid,expected_revision integer,new_bike text,new_name text,new_phone text,new_plate text,service_codes text[],options jsonb,expected_price_fingerprint text default null)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare booking public.herco_bookings;previous herco_private.booking_service_changes;normalized jsonb;selected text[];old_lines jsonb;new_lines jsonb;old_options jsonb;editable boolean;
 bk text:=btrim(coalesce(new_bike,''));nm text:=btrim(coalesce(new_name,''));ph text:=btrim(coalesce(new_phone,''));pl text:=btrim(coalesce(new_plate,''));
begin
 if request_id is null or expected_revision is null or expected_revision<0 or coalesce(cardinality(service_codes),0) not between 1 and 20 or array_position(service_codes,null) is not null then raise exception 'Choose valid services.' using errcode='22023';end if;
 if new_bike is null or new_name is null or new_phone is null or new_plate is null then raise exception 'Check the motorcycle and contact details.' using errcode='22023';end if;
 if char_length(bk) not between 1 and 120 then raise exception 'Enter the motorcycle (up to 120 characters).' using errcode='22023';end if;
 if char_length(nm) not between 1 and 120 then raise exception 'Enter your name (up to 120 characters).' using errcode='22023';end if;
 if ph<>'' and char_length(ph) not between 3 and 40 then raise exception 'Enter a valid mobile number, or leave it blank.' using errcode='22023';end if;
 if char_length(pl)>30 then raise exception 'The plate number is too long.' using errcode='22023';end if;
 select b.* into booking from public.herco_bookings b where b.id=booking_id for update;
 if not found then raise exception 'Booking not found.' using errcode='P0002';end if;
 editable:=herco_private.may_edit_booked_services(booking);
 normalized:=herco_private.normalize_coating_options(options,service_codes,bk);
 select array_agg(distinct code order by code) into selected from unnest(service_codes)code;
 if cardinality(selected)<>cardinality(service_codes) then raise exception 'Choose each service once.' using errcode='22023';end if;
 select c.* into previous from herco_private.booking_service_changes c where c.booking_id=booking.id and c.actor_id=auth.uid() and c.request_id=herco_edit_booking_configured.request_id;
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
 new_lines:=herco_private.coating_price_lines(new_lines,bk,normalized);
 perform herco_private.require_unchanged_preview(new_lines,expected_price_fingerprint);
 if new_lines=old_lines and normalized=old_options and bk is not distinct from booking.bike
  and nm=coalesce(booking.customer_contact->>'name','') and ph=coalesce(booking.customer_contact->>'phone','') and pl=coalesce(booking.customer_contact->>'plate','')
  then return public.herco_booked_services(booking.id);end if;
 update public.herco_bookings b set bike=bk,customer_contact=jsonb_build_object('name',nm,'phone',ph,'email',b.customer_contact->>'email','plate',pl),
  current_services=new_lines,current_total_centavos=herco_private.price_line_total(new_lines),current_coating_options=normalized,service_revision=b.service_revision+1 where b.id=booking.id;
 insert into herco_private.booking_service_changes(booking_id,actor_id,request_id,revision,service_codes,before_services,after_services,before_options,after_options)values(booking.id,auth.uid(),request_id,expected_revision+1,selected,old_lines,new_lines,old_options,normalized);
 insert into public.herco_booking_events(booking_id,actor_id,kind,to_status)values(booking.id,auth.uid(),'booking_services_updated',booking.status);
 return public.herco_booked_services(booking.id);
end $$;

revoke all on function public.herco_booked_services(uuid),
  public.herco_edit_booking_configured(uuid, uuid, integer, text, text, text, text, text[], jsonb, text) from public, anon, authenticated;
grant execute on function public.herco_booked_services(uuid),
  public.herco_edit_booking_configured(uuid, uuid, integer, text, text, text, text, text[], jsonb, text) to authenticated;

notify pgrst, 'reload schema';
commit;
