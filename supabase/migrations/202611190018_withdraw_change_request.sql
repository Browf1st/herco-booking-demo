begin;

alter table herco_private.booking_change_requests
  drop constraint booking_change_requests_state_check,
  add constraint booking_change_requests_state_check check (state in ('pending', 'approved', 'declined', 'withdrawn')),
  add column withdrawn_at timestamptz,
  add constraint booking_change_requests_withdrawn_at_check check ((state = 'withdrawn') = (withdrawn_at is not null));

create function public.herco_withdraw_booking_change(request_id uuid)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare actor uuid := auth.uid();
  booking public.herco_bookings;
  request herco_private.booking_change_requests;
begin
  if actor is null then raise exception 'Sign in first.' using errcode = '42501'; end if;
  select r.* into request from herco_private.booking_change_requests r where r.id = request_id and r.customer_id = actor;
  if not found then raise exception 'Request not found.' using errcode = 'P0002'; end if;
  select b.* into strict booking from public.herco_bookings b where b.id = request.booking_id and b.customer_id = actor for update;
  select r.* into strict request from herco_private.booking_change_requests r where r.id = request_id for update;
  if request.state = 'withdrawn' then return; end if;
  if request.state <> 'pending' then raise exception 'The shop already reviewed this request.' using errcode = '23P01'; end if;

  update herco_private.booking_change_requests r set state = 'withdrawn', withdrawn_at = clock_timestamp()
    where r.id = request_id;
  insert into public.herco_booking_events(booking_id, actor_id, kind, to_status)
    values (booking.id, actor, 'booking_' || request.kind || '_withdrawn', booking.status);
end;
$$;

revoke all on function public.herco_withdraw_booking_change(uuid) from public, anon, authenticated;
grant execute on function public.herco_withdraw_booking_change(uuid) to authenticated;

commit;
