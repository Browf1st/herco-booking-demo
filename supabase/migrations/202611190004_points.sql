begin;

create table herco_private.point_rewards (
  id uuid primary key default gen_random_uuid(),
  label text not null check (char_length(btrim(label)) between 1 and 120),
  cost integer not null check (cost > 0),
  enabled boolean not null default false
);

create table herco_private.point_receipts (
  id uuid primary key default gen_random_uuid(),
  member_id uuid not null references auth.users(id),
  request_id uuid not null,
  reward_id uuid not null references herco_private.point_rewards(id),
  reward_label text not null,
  cost integer not null check (cost > 0),
  created_at timestamptz not null default now(),
  approved_by uuid references auth.users(id),
  approved_at timestamptz,
  claimed_by uuid references auth.users(id),
  claimed_at timestamptz,
  unique (member_id, request_id),
  check ((approved_at is null) = (approved_by is null)),
  check ((claimed_at is null) = (claimed_by is null)),
  check (claimed_at is null or approved_at is not null)
);

create table herco_private.point_entries (
  id bigint generated always as identity primary key,
  member_id uuid not null references auth.users(id),
  actor_id uuid not null references auth.users(id),
  amount integer not null check (amount <> 0),
  reason text not null check (char_length(btrim(reason)) between 1 and 300),
  receipt_id uuid unique references herco_private.point_receipts(id),
  request_id uuid,
  created_at timestamptz not null default now(),
  unique (actor_id, request_id)
);

create index point_entries_member_idx on herco_private.point_entries(member_id, created_at desc, id desc);
create index point_receipts_member_idx on herco_private.point_receipts(member_id, created_at desc, id desc);
alter table herco_private.point_rewards enable row level security;
alter table herco_private.point_receipts enable row level security;
alter table herco_private.point_entries enable row level security;
revoke all on herco_private.point_rewards, herco_private.point_receipts, herco_private.point_entries
  from public, anon, authenticated;

create function herco_private.check_point_staff(action text)
returns void language plpgsql stable set search_path = '' as $$
begin
  if (auth.jwt()->>'aal') is distinct from 'aal2' or not exists (
    select 1 from herco_private.staff_memberships s
    where s.user_id = auth.uid() and s.enabled and 'HERCO Points' = any(s.page_grants)
      and (action is null or action = any(s.action_grants))
  ) then
    raise exception 'Points access requires staff permission and MFA.' using errcode = '42501';
  end if;
end;
$$;
revoke all on function herco_private.check_point_staff(text) from public, anon, authenticated;

create function public.herco_my_points()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare member uuid := auth.uid();
begin
  if member is null then raise exception 'Sign in to see your points.' using errcode = '42501'; end if;
  return jsonb_build_object(
    'balance', (select coalesce(sum(e.amount), 0) from herco_private.point_entries e where e.member_id = member),
    'rewards', (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'label', r.label, 'cost', r.cost)
      order by r.cost, r.id), '[]'::jsonb) from herco_private.point_rewards r where r.enabled),
    'receipts', (select coalesce(jsonb_agg(to_jsonb(r) order by r.created_at desc, r.id desc), '[]'::jsonb)
      from (select p.id, p.reward_label, p.cost, p.created_at, p.approved_at, p.claimed_at
        from herco_private.point_receipts p where p.member_id = member order by p.created_at desc, p.id desc limit 50) r)
  );
end;
$$;

create function public.herco_redeem_points(reward_id uuid, request_id uuid)
returns uuid language plpgsql volatile security definer set search_path = '' as $$
declare member uuid := auth.uid();
  existing herco_private.point_receipts;
  reward herco_private.point_rewards;
  receipt uuid;
begin
  if member is null or not exists (select 1 from auth.users u where u.id = member and u.email_confirmed_at is not null) then
    raise exception 'Sign in with a verified email.' using errcode = '42501';
  end if;
  if reward_id is null or request_id is null then raise exception 'Select a reward.' using errcode = '22023'; end if;
  perform pg_advisory_xact_lock(72003, hashtext(member::text));
  select p.* into existing from herco_private.point_receipts p
    where p.member_id = member and p.request_id = herco_redeem_points.request_id;
  if found then
    if existing.reward_id <> reward_id then raise exception 'Request ID already used.' using errcode = '22023'; end if;
    return existing.id;
  end if;
  select r.* into reward from herco_private.point_rewards r where r.id = reward_id and r.enabled for share;
  if not found then raise exception 'That reward is unavailable.' using errcode = '22023'; end if;
  if (select coalesce(sum(e.amount), 0) from herco_private.point_entries e where e.member_id = member) < reward.cost then
    raise exception 'You need more points for this reward.' using errcode = '23514';
  end if;
  insert into herco_private.point_receipts (member_id, request_id, reward_id, reward_label, cost)
    values (member, request_id, reward.id, reward.label, reward.cost) returning id into receipt;
  insert into herco_private.point_entries(member_id, actor_id, amount, reason, receipt_id)
    values (member, member, -reward.cost, 'Redeemed ' || reward.label, receipt);
  return receipt;
end;
$$;

create function public.herco_adjust_points(member uuid, delta integer, reason text, request_id uuid)
returns bigint language plpgsql volatile security definer set search_path = '' as $$
declare normalized text := btrim(reason);
  entry herco_private.point_entries;
begin
  perform herco_private.check_point_staff('managePoints');
  if member is null or delta is null or delta = 0 or normalized is null or
    char_length(normalized) not between 1 and 300 or request_id is null then
    raise exception 'Enter a member, points, and a reason.' using errcode = '22023';
  end if;
  perform pg_advisory_xact_lock(72004, hashtext(auth.uid()::text || ':' || request_id::text));
  perform pg_advisory_xact_lock(72003, hashtext(member::text));
  select e.* into entry from herco_private.point_entries e
    where e.actor_id = auth.uid() and e.request_id = herco_adjust_points.request_id;
  if found then
    if entry.member_id <> member or entry.amount <> delta or entry.reason <> normalized then
      raise exception 'Request ID already used.' using errcode = '22023';
    end if;
    return entry.id;
  end if;
  if (select coalesce(sum(e.amount), 0) from herco_private.point_entries e where e.member_id = member) + delta < 0 then
    raise exception 'This correction would leave a negative balance.' using errcode = '23514';
  end if;
  insert into herco_private.point_entries(member_id, actor_id, amount, reason, request_id)
    values (member, auth.uid(), delta, normalized, herco_adjust_points.request_id) returning id into entry.id;
  return entry.id;
end;
$$;

create function public.herco_review_point_receipt(receipt uuid, decision text)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare current_receipt herco_private.point_receipts;
begin
  if decision is null or decision not in ('approve', 'claim') then
    raise exception 'Invalid reward action.' using errcode = '22023';
  end if;
  perform herco_private.check_point_staff(case decision when 'approve' then 'approveRewards' else 'claimRewards' end);
  select p.* into current_receipt from herco_private.point_receipts p where p.id = receipt for update;
  if not found then raise exception 'Reward receipt not found.' using errcode = '22023'; end if;
  if decision = 'approve' and current_receipt.approved_at is null then
    update herco_private.point_receipts set approved_at = now(), approved_by = auth.uid() where id = receipt;
  elsif decision = 'claim' and current_receipt.claimed_at is null then
    if current_receipt.approved_at is null then raise exception 'Approve this reward first.' using errcode = '23514'; end if;
    update herco_private.point_receipts set claimed_at = now(), claimed_by = auth.uid() where id = receipt;
  end if;
end;
$$;

create function public.herco_staff_points()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform herco_private.check_point_staff(null);
  return jsonb_build_object(
    'actions', (select s.action_grants from herco_private.staff_memberships s where s.user_id = auth.uid()),
    'receipts', (select coalesce(jsonb_agg(to_jsonb(r) order by r.created_at desc, r.id desc), '[]'::jsonb)
      from (select p.id, p.member_id, p.reward_label, p.cost, p.created_at, p.approved_at,
        p.approved_by, p.claimed_at, p.claimed_by from herco_private.point_receipts p
        order by p.created_at desc, p.id desc limit 50) r),
    'rewards', (select coalesce(jsonb_agg(to_jsonb(r) order by r.cost, r.id), '[]'::jsonb)
      from herco_private.point_rewards r)
  );
end;
$$;

create function public.herco_save_point_reward(reward_id uuid, reward_label text, points_cost integer, active boolean)
returns uuid language plpgsql volatile security definer set search_path = '' as $$
declare saved uuid;
begin
  perform herco_private.check_point_staff('manageRewards');
  if reward_id is null or reward_label is null or char_length(btrim(reward_label)) not between 1 and 120
    or points_cost is null or points_cost < 1 or active is null then
    raise exception 'Enter a reward name and point cost.' using errcode = '22023';
  end if;
  insert into herco_private.point_rewards(id, label, cost, enabled)
    values (reward_id, btrim(reward_label), points_cost, active)
    on conflict (id) do update set label = excluded.label, cost = excluded.cost, enabled = excluded.enabled
    returning id into saved;
  return saved;
end;
$$;

revoke all on function public.herco_my_points(), public.herco_redeem_points(uuid, uuid),
  public.herco_adjust_points(uuid, integer, text, uuid), public.herco_review_point_receipt(uuid, text)
  , public.herco_staff_points(), public.herco_save_point_reward(uuid, text, integer, boolean)
  from public, anon, authenticated;
grant execute on function public.herco_my_points(), public.herco_redeem_points(uuid, uuid),
  public.herco_adjust_points(uuid, integer, text, uuid), public.herco_review_point_receipt(uuid, text)
  , public.herco_staff_points(), public.herco_save_point_reward(uuid, text, integer, boolean)
  to authenticated;

commit;
