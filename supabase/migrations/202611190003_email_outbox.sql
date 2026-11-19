alter table herco_private.notification_outbox
  add column lease_token uuid,
  add column skipped_at timestamptz,
  add column review_at timestamptz,
  add column last_outcome text;

create index herco_outbox_ready on herco_private.notification_outbox (available_at, id)
  where lease_until is null and sent_at is null and failed_at is null
    and skipped_at is null and review_at is null;

create index herco_outbox_expired_leases on herco_private.notification_outbox (lease_until, id)
  where lease_until is not null;

-- An expired claim might have sent mail and died before recording the provider response.
-- Quarantine it for reconciliation rather than risking a duplicate.
create function public.herco_claim_notification_outbox(batch_size integer default 5)
returns table (
  id text,
  lease_token uuid,
  template text,
  recipient text,
  payload jsonb
)
language plpgsql volatile security definer set search_path = '' as $$
declare
  claimed_at timestamptz := statement_timestamp();
  claim_token uuid := gen_random_uuid();
begin
  if batch_size is null or batch_size not between 1 and 5 then
    raise exception 'Choose a batch size from 1 to 5.' using errcode = '22023';
  end if;

  with expired as (
    select o.id
    from herco_private.notification_outbox as o
    where o.lease_until <= claimed_at
      and o.sent_at is null and o.failed_at is null
      and o.skipped_at is null and o.review_at is null
    order by o.lease_until, o.id
    limit batch_size
    for update skip locked
  )
  update herco_private.notification_outbox as o
  set review_at = claimed_at, last_outcome = 'expired-lease',
    lease_until = null, lease_token = null
  from expired
  where o.id = expired.id;

  return query
    with ready as (
      select o.id
      from herco_private.notification_outbox as o
      where o.available_at <= claimed_at and o.lease_until is null
        and o.sent_at is null and o.failed_at is null
        and o.skipped_at is null and o.review_at is null
        and o.attempts < 5
      order by o.available_at, o.id
      limit batch_size
      for update skip locked
    )
    update herco_private.notification_outbox as o
    set lease_until = claimed_at + interval '2 minutes',
      lease_token = claim_token, attempts = o.attempts + 1
    from ready
    where o.id = ready.id
    returning o.id::text, o.lease_token, o.template, o.recipient, o.payload;
end;
$$;

create function public.herco_settle_notification_outbox(
  job_id bigint, claim_token uuid, outcome text, provider_id text default null,
  retry_after_seconds integer default null
)
returns boolean
language plpgsql volatile security definer set search_path = '' as $$
declare
  settled_at timestamptz := statement_timestamp();
begin
  if outcome is null or outcome not in ('accepted', 'recipient-not-allowed', 'rate-limited',
    'rejected', 'ambiguous', 'invalid-template')
    or (outcome = 'accepted' and (provider_id is null or length(btrim(provider_id)) not between 1 and 500)) then
    raise exception 'Invalid notification outcome.' using errcode = '22023';
  end if;

  update herco_private.notification_outbox as o
  set lease_until = null, lease_token = null,
    sent_at = case when outcome = 'accepted' then settled_at end,
    provider_message_id = case when outcome = 'accepted' then btrim(provider_id) end,
    skipped_at = case when outcome = 'recipient-not-allowed' then settled_at end,
    review_at = case when outcome = 'ambiguous' then settled_at end,
    failed_at = case when outcome in ('rejected', 'invalid-template')
      or (outcome = 'rate-limited' and o.attempts >= 5) then settled_at end,
    available_at = case when outcome = 'rate-limited' and o.attempts < 5
      then settled_at + make_interval(secs => least(86400, greatest(
        60 * (1 << (o.attempts - 1)), coalesce(retry_after_seconds, 0))))
      else o.available_at end,
    last_outcome = outcome
  where o.id = job_id and o.lease_token = claim_token and o.lease_until > settled_at
    and o.sent_at is null and o.failed_at is null
    and o.skipped_at is null and o.review_at is null;
  return found;
end;
$$;

revoke all on function public.herco_claim_notification_outbox(integer),
  public.herco_settle_notification_outbox(bigint, uuid, text, text, integer)
  from public, anon, authenticated;
grant execute on function public.herco_claim_notification_outbox(integer),
  public.herco_settle_notification_outbox(bigint, uuid, text, text, integer)
  to service_role;
