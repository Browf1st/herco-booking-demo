begin;

alter table herco_private.staff_memberships
  add column revision integer not null default 1 check (revision >= 1);

create table herco_private.staff_access_audit (
  id bigint generated always as identity primary key,
  actor_id uuid not null,
  target_id uuid not null,
  occurred_at timestamptz not null default clock_timestamp(),
  previous_state jsonb,
  new_state jsonb not null,
  check (actor_id <> target_id)
);
alter table herco_private.staff_access_audit enable row level security;
revoke all on herco_private.staff_access_audit from public, anon, authenticated;

create function herco_private.staff_delegation_catalog()
returns table (page text, action text, label text)
language sql immutable set search_path = '' as $$
  values
    ('Bookings', 'createBooking', 'Create manual bookings'),
    ('Bookings', 'manageSchedule', 'Manage availability'),
    ('Bookings', 'confirmBooking', 'Confirm bookings'),
    ('Bookings', 'cancelBooking', 'Cancel bookings directly'),
    ('Bookings', 'rescheduleBooking', 'Reschedule bookings directly'),
    ('Bookings', 'editServices', 'Edit booked services'),
    ('Bookings', 'adjustPrices', 'Adjust individual booking prices'),
    ('Bookings', 'completeBooking', 'Complete bookings and attach photos'),
    ('Change requests', 'reviewCancellation', 'Review cancellation requests'),
    ('Change requests', 'reviewReschedule', 'Review reschedule requests'),
    ('Booking history', 'completeBooking', 'Complete bookings and attach photos'),
    ('Customers', null, null),
    ('HERCO Points', 'managePoints', 'Grant or correct points'),
    ('HERCO Points', 'manageRewards', 'Edit rewards'),
    ('HERCO Points', 'approveRewards', 'Review reward redemptions'),
    ('HERCO Points', 'claimRewards', 'Mark rewards as claimed'),
    ('Inventory', 'manageInventory', 'Manage inventory and stock'),
    ('Reports', 'viewIncome', 'View completed service value and final prices'),
    ('Pricing', 'changePricing', 'Change service catalog prices'),
    ('Pricing', 'changePromotions', 'Change promotions')
$$;

create function herco_private.staff_management_actor()
returns herco_private.staff_memberships
language plpgsql volatile set search_path = '' as $$
declare
  member herco_private.staff_memberships;
begin
  if auth.uid() is null or (auth.jwt()->>'aal') is distinct from 'aal2' then
    raise exception 'Verify your staff session first.' using errcode = '42501';
  end if;

  select m.* into member from herco_private.staff_memberships m
  where m.user_id = auth.uid() and m.enabled and m.role in ('owner', 'superadmin')
    and 'Staff Access' = any(m.page_grants) and 'manageStaff' = any(m.action_grants)
  for share;
  if not found then
    raise exception 'You do not have access to manage staff.' using errcode = '42501';
  end if;
  return member;
end
$$;

create function public.herco_staff_access()
returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  member herco_private.staff_memberships := herco_private.staff_management_actor();
  pages jsonb;
  actions jsonb;
  people jsonb;
begin
  select jsonb_agg(c.page order by c.page) into pages
  from (select distinct page from herco_private.staff_delegation_catalog()) c
  where c.page = any(member.page_grants);

  select jsonb_agg(jsonb_build_object('page', c.page, 'key', c.action, 'label', c.label) order by c.page, c.label)
  into actions from herco_private.staff_delegation_catalog() c
  where c.page = any(member.page_grants) and c.action = any(member.action_grants);

  select jsonb_agg(jsonb_build_object(
    'userId', m.user_id, 'email', u.email, 'role', m.role, 'enabled', m.enabled,
    'pages', m.page_grants, 'actions', m.action_grants, 'revision', m.revision
  ) order by u.email, m.user_id)
  into people from herco_private.staff_memberships m
  join auth.users u on u.id = m.user_id
  where m.role in ('staff', 'admin', 'restricted_admin')
    and u.email_confirmed_at is not null and u.email is not null
    and m.page_grants <@ member.page_grants and m.action_grants <@ member.action_grants;
  return jsonb_build_object('pages', coalesce(pages, '[]'::jsonb), 'actions', coalesce(actions, '[]'::jsonb), 'members', coalesce(people, '[]'::jsonb));
end
$$;

create function public.herco_save_staff_access(
  p_target_id uuid, p_email text, p_role text, p_enabled boolean,
  p_page_grants text[], p_action_grants text[], p_expected_revision integer
)
returns void
language plpgsql volatile security definer set search_path = '' as $$
declare
  member herco_private.staff_memberships := herco_private.staff_management_actor();
  target uuid := p_target_id;
  matches uuid[];
  previous herco_private.staff_memberships;
  saved herco_private.staff_memberships;
begin
  if p_role is null or p_role not in ('staff', 'admin', 'restricted_admin')
    or p_enabled is null or p_page_grants is null or p_action_grants is null
    or cardinality(p_page_grants) > 20 or cardinality(p_action_grants) > 40
    or array_position(p_page_grants, null) is not null or array_position(p_action_grants, null) is not null
    or ((target is null) = (p_email is null))
    or (target is null and (p_expected_revision is not null or char_length(p_email) not between 3 and 254))
    or (target is not null and (p_expected_revision is null or p_expected_revision < 1)) then
    raise exception 'Check the staff account and permissions.' using errcode = '22023';
  end if;

  if (p_page_grants <@ member.page_grants and p_action_grants <@ member.action_grants) is not true then
    raise exception 'You can only grant your own access.' using errcode = '42501';
  end if;
  if exists (
    select 1 from unnest(p_page_grants) p(value)
    where not exists (select 1 from herco_private.staff_delegation_catalog() c where c.page = p.value)
  ) or exists (
    select 1 from unnest(p_action_grants) a(value)
    where not exists (
      select 1 from herco_private.staff_delegation_catalog() c where c.action = a.value and c.page = any(p_page_grants)
    )
  ) then
    raise exception 'Select the matching page for each action.' using errcode = '22023';
  end if;

  if target is null then
    select array_agg(u.id) into matches from (
      select users.id from auth.users users
      where lower(users.email) = lower(btrim(p_email)) and users.email_confirmed_at is not null
      limit 2
    ) u;
    if cardinality(matches) is distinct from 1 then
      raise exception 'Ask this person to create and verify a HERCO account first.' using errcode = 'P0002';
    end if;
    target := matches[1];
  end if;
  if target = member.user_id then
    raise exception 'You cannot change your own staff access.' using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('staff-access:' || target::text, 0));
  perform 1 from auth.users u where u.id = target and u.email is not null and u.email_confirmed_at is not null for share;
  if not found then
    raise exception 'Ask this person to create and verify a HERCO account first.' using errcode = 'P0002';
  end if;
  select m.* into previous from herco_private.staff_memberships m where m.user_id = target for update;

  if found then
    if previous.role not in ('staff', 'admin', 'restricted_admin')
      or (previous.page_grants <@ member.page_grants and previous.action_grants <@ member.action_grants) is not true then
      raise exception 'You cannot change this staff account.' using errcode = '42501';
    end if;
    if previous.revision is distinct from p_expected_revision then
      raise exception 'This staff account changed. Reload before saving.' using errcode = '40001';
    end if;
    update herco_private.staff_memberships
    set role = p_role, enabled = p_enabled,
      page_grants = array(select distinct p from unnest(p_page_grants) p order by p),
      action_grants = array(select distinct a from unnest(p_action_grants) a order by a),
      revision = revision + 1
    where user_id = target returning * into saved;
  else
    if p_expected_revision is not null then
      raise exception 'This staff account changed. Reload before saving.' using errcode = '40001';
    end if;
    insert into herco_private.staff_memberships(user_id, role, enabled, page_grants, action_grants)
    values (
      target, p_role, p_enabled,
      array(select distinct p from unnest(p_page_grants) p order by p),
      array(select distinct a from unnest(p_action_grants) a order by a)
    ) returning * into saved;
  end if;

  insert into herco_private.staff_access_audit(actor_id, target_id, previous_state, new_state)
  values (member.user_id, target, case when previous.user_id is not null then to_jsonb(previous) end, to_jsonb(saved));
end
$$;

revoke all on function herco_private.staff_delegation_catalog(), herco_private.staff_management_actor()
  from public, anon, authenticated;
revoke all on function public.herco_staff_access(), public.herco_save_staff_access(uuid, text, text, boolean, text[], text[], integer)
  from public, anon, authenticated;
grant execute on function public.herco_staff_access(), public.herco_save_staff_access(uuid, text, text, boolean, text[], text[], integer)
  to authenticated;

commit;
