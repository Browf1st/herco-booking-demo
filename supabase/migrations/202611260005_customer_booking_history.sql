-- F-024: customer-safe booking history (the change log on My Bookings).
-- OWNER-AUTHORIZED HOSTED RELEASE STEP: apply together with the Worker route GET /api/bookings/history.
-- Read-only and additive: nothing is written or rewritten. It is a customer-safe slice of the same sources as the staff
-- herco_booking_history (price edits, price corrections, service changes, status events).
-- Only the booking's own customer may read it. It never selects reasons, staff names, notes, phone or email.
begin;

create function public.herco_customer_booking_history(booking uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  b public.herco_bookings;
  result jsonb;
begin
  if auth.uid() is null or booking is null then
    raise exception 'You cannot see this booking history.' using errcode = '42501';
  end if;
  -- One answer for "not yours" and "does not exist", so booking ids cannot be probed.
  select x.* into b from public.herco_bookings x where x.id = booking and x.customer_id = auth.uid();
  if not found then raise exception 'You cannot see this booking history.' using errcode = '42501'; end if;

  select coalesce(jsonb_agg(top.entry order by top.happened desc, top.src desc, top.seq desc), '[]'::jsonb) into result from (
    select r.happened, r.src, r.seq,
      jsonb_strip_nulls(jsonb_build_object('at', r.happened, 'kind', r.kind,
        'actor', case when r.actor_id = b.customer_id then 'you' else 'shop' end,
        'service_label', r.service_label, 'from_centavos', r.old_c, 'to_centavos', r.new_c)) as entry
    from (
      select e.recorded_at as happened, 1 as src, e.revision::bigint as seq, e.actor_id, 'price_changed'::text as kind,
        e.service_label, e.previous_centavos as old_c, e.new_centavos as new_c
      from herco_private.booking_price_edits e where e.booking_id = b.id
      union all
      select c.recorded_at, 2, c.revision::bigint, c.actor_id, 'price_corrected',
        coalesce((select l->>'label' from jsonb_array_elements(coalesce(b.current_services, b.original_services)) l where l->>'code' = c.service_code limit 1),
          (select l->>'label' from jsonb_array_elements(b.original_services) l where l->>'code' = c.service_code limit 1), c.service_code),
        c.previous_centavos, c.corrected_centavos
      from herco_private.booking_price_corrections c where c.booking_id = b.id
      union all
      select s.recorded_at, 3, s.revision::bigint, s.actor_id, 'service_added', coalesce(a->>'label', a->>'code'),
        null::bigint, (a->>'price_centavos')::bigint
      from herco_private.booking_service_changes s cross join lateral jsonb_array_elements(s.after_services) a
      where s.booking_id = b.id
        and not exists (select 1 from jsonb_array_elements(s.before_services) o where o->>'code' = a->>'code')
      union all
      select s.recorded_at, 3, s.revision::bigint, s.actor_id, 'service_removed', coalesce(o->>'label', o->>'code'),
        (o->>'price_centavos')::bigint, null::bigint
      from herco_private.booking_service_changes s cross join lateral jsonb_array_elements(s.before_services) o
      where s.booking_id = b.id
        and not exists (select 1 from jsonb_array_elements(s.after_services) a where a->>'code' = o->>'code')
      union all
      select ev.created_at, 4, ev.id, ev.actor_id,
        case when ev.kind in ('booking_submitted', 'walk_in_submitted', 'booking_created_by_staff') then 'booked'
          when ev.kind in ('booking_confirmed', 'walk_in_confirmed') then 'approved'
          when ev.kind = 'completed' then 'completed'
          when ev.kind in ('booking_cancel_approved', 'booking_cancelled_by_staff') then 'cancelled'
          else 'rescheduled' end,
        null::text, null::bigint, null::bigint
      from public.herco_booking_events ev where ev.booking_id = b.id
        and ev.kind in ('booking_submitted', 'walk_in_submitted', 'booking_created_by_staff', 'booking_confirmed', 'walk_in_confirmed',
          'completed', 'booking_cancel_approved', 'booking_cancelled_by_staff', 'booking_reschedule_approved', 'booking_rescheduled_by_staff')
    ) r
    order by r.happened desc, r.src desc, r.seq desc limit 200
  ) top;
  return jsonb_build_object('booking_id', b.id, 'entries', result);
end;
$$;
revoke all on function public.herco_customer_booking_history(uuid) from public, anon, authenticated;
grant execute on function public.herco_customer_booking_history(uuid) to authenticated;

notify pgrst, 'reload schema';
commit;
