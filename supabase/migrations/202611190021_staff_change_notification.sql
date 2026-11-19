begin;

create table herco_private.staff_notification_settings (
  singleton boolean primary key default true check (singleton),
  change_request_inbox text check (change_request_inbox is null or (
    char_length(change_request_inbox) <= 254 and
    change_request_inbox ~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$'
  ))
);

insert into herco_private.staff_notification_settings default values;
alter table herco_private.staff_notification_settings enable row level security;
revoke all on herco_private.staff_notification_settings from public, anon, authenticated;

create function herco_private.enqueue_staff_change_notification()
returns trigger
language plpgsql volatile set search_path = '' as $$
begin
  insert into herco_private.notification_outbox (event_id, template, recipient, payload)
  select new.id, 'staff_' || new.kind, settings.change_request_inbox,
    jsonb_strip_nulls(jsonb_build_object(
      'booking_id', request.booking_id,
      'request_id', request.id,
      'visit_date', request.original_date,
      'visit_hour', request.original_hour,
      'target_date', request.target_date,
      'target_hour', request.target_hour
    ))
  from herco_private.booking_change_requests as request
  cross join herco_private.staff_notification_settings as settings
  where request.booking_id = new.booking_id and request.customer_id = new.actor_id
    and request.state = 'pending' and 'booking_' || request.kind || '_requested' = new.kind
    and settings.singleton and settings.change_request_inbox is not null
  on conflict (event_id, template) do nothing;
  return new;
end;
$$;

create trigger herco_enqueue_staff_change_notification
after insert on public.herco_booking_events
for each row
when (new.kind in ('booking_cancel_requested', 'booking_reschedule_requested'))
execute function herco_private.enqueue_staff_change_notification();

create function public.herco_check_staff_change_outbox(job_id bigint, claim_token uuid)
returns text
language plpgsql volatile security definer set search_path = '' as $$
declare
  claimed herco_private.notification_outbox;
  checked_at timestamptz := statement_timestamp();
begin
  select o.* into claimed
  from herco_private.notification_outbox as o
  where o.id = job_id and o.lease_token = claim_token and o.lease_until > checked_at
    and o.template in ('staff_booking_cancel_requested', 'staff_booking_reschedule_requested')
    and o.sent_at is null and o.failed_at is null and o.skipped_at is null and o.review_at is null
  for update;
  if not found then return null; end if;

  if exists (
    select 1
    from public.herco_booking_events as event
    join herco_private.booking_change_requests as request on request.booking_id = event.booking_id
    cross join herco_private.staff_notification_settings as settings
    where event.id = claimed.event_id and 'staff_' || event.kind = claimed.template
      and request.customer_id = event.actor_id and request.state = 'pending'
      and to_jsonb(request.id) = claimed.payload->'request_id'
      and 'staff_booking_' || request.kind || '_requested' = claimed.template
      and settings.singleton and settings.change_request_inbox = claimed.recipient
  ) then return 'ready'; end if;

  update herco_private.notification_outbox as o
  set lease_until = null, lease_token = null, skipped_at = checked_at, last_outcome = 'stale'
  where o.id = claimed.id;
  return 'stale';
end;
$$;

revoke all on function herco_private.enqueue_staff_change_notification(),
  public.herco_check_staff_change_outbox(bigint, uuid) from public, anon, authenticated;
grant execute on function public.herco_check_staff_change_outbox(bigint, uuid) to service_role;

commit;
