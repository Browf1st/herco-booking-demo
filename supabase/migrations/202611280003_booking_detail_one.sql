-- Owner decision 2026-11-28: the staff view of a customer's booking history (Customers directory) must let staff
-- open the full "More details" popup per booking, the same one Reports uses. This returns ONE booking's full staff
-- record (same shape as a herco_staff_booking_records row), gated to staff who can see bookings or customers.
-- Amounts follow the same viewIncome rule as everywhere else.
create function public.herco_staff_booking_detail(booking uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare member herco_private.staff_memberships; b public.herco_bookings; show_income boolean;
  final_c bigint; correction_c bigint;
begin
  if not herco_private.has_verified_staff_session() then raise exception 'Staff access required.' using errcode='42501'; end if;
  select * into member from herco_private.staff_memberships m where m.user_id=auth.uid() and m.enabled
    and m.page_grants && array['Customers','Bookings','Booking history','Reports'];
  if not found then raise exception 'You cannot access this booking.' using errcode='42501'; end if;
  if booking is null then raise exception 'Choose a booking.' using errcode='22023'; end if;
  select * into b from public.herco_bookings x where x.id=booking;
  if not found then raise exception 'Booking not found.' using errcode='P0002'; end if;
  show_income:='viewIncome'=any(member.action_grants);
  select c.final_price_centavos into final_c from herco_private.booking_completion c where c.booking_id=b.id;
  select p.corrected_completed_centavos into correction_c from herco_private.booking_price_corrections p
    where p.booking_id=b.id and p.corrected_completed_centavos is not null order by p.revision desc limit 1;
  return herco_private.staff_booking_record(b)
    || jsonb_build_object('canViewIncome',show_income)
    || case when show_income then jsonb_build_object(
      'final_price_centavos',coalesce(correction_c,final_c),'original_total_centavos',b.original_total_centavos)
    else jsonb_build_object('final_price_centavos',null,'original_total_centavos',null,'total_centavos',null,
      'original_services',herco_private.strip_service_money(b.original_services),
      'current_services',herco_private.strip_service_money(coalesce(b.current_services,b.original_services))) end;
end;
$$;
revoke all on function public.herco_staff_booking_detail(uuid) from public,anon,authenticated;
grant execute on function public.herco_staff_booking_detail(uuid) to authenticated;
