begin;

alter table public.herco_customer_profiles
  add column leaderboard_opt_in boolean not null default false,
  add column leaderboard_alias text not null default '' check (char_length(leaderboard_alias) <= 40);

create function public.herco_reward_preview()
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'label',r.label,'scope',r.scope,'cost',r.cost)
    order by r.cost,r.id),'[]'::jsonb) from herco_private.point_rewards r where r.enabled;
$$;
revoke all on function public.herco_reward_preview() from public,anon,authenticated;
grant execute on function public.herco_reward_preview() to anon,authenticated;

create or replace function public.herco_my_points()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare member uuid := auth.uid(); profile_name text; ranking jsonb; own_rank bigint;
begin
  if member is null then raise exception 'Sign in to see your points.' using errcode='42501'; end if;
  select coalesce(nullif(p.display_name,''),nullif(to_jsonb(u)->'raw_user_meta_data'->>'full_name',''),'HERCO member')
    into profile_name from auth.users u left join public.herco_customer_profiles p on p.user_id=u.id where u.id=member;
  with balances as (
    select u.id, case when u.id=member then profile_name else p.leaderboard_alias end as label,
      coalesce(sum(e.amount),0) as balance
    from auth.users u left join public.herco_customer_profiles p on p.user_id=u.id
    left join herco_private.point_entries e on e.member_id=u.id
    where u.email_confirmed_at is not null and (u.id=member or (p.leaderboard_opt_in and btrim(p.leaderboard_alias)<>''))
    group by u.id,p.leaderboard_alias
  ), ranked as (select *,row_number() over(order by balance desc,id) as position from balances)
  select coalesce(jsonb_agg(jsonb_build_object('position',position,'name',label,'balance',balance,'isCurrent',id=member)
    order by position) filter(where position<=10),'[]'::jsonb),max(position) filter(where id=member)
    into ranking,own_rank from ranked;
  return jsonb_build_object(
    'memberId',member,'memberName',profile_name,'ownRank',own_rank,'ranking',ranking,
    'balance',(select coalesce(sum(e.amount),0) from herco_private.point_entries e where e.member_id=member),
    'rewards',public.herco_reward_preview(),
    'ledger',(select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc,x.id desc),'[]'::jsonb)
      from (select e.id,e.amount,e.reason,e.created_at from herco_private.point_entries e
        where e.member_id=member order by e.created_at desc,e.id desc limit 100) x),
    'receipts',(select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc,x.id desc),'[]'::jsonb)
      from (select p.id,p.reference,p.reward_label,p.reward_scope,p.cost,p.balance_after,p.member_name,
        p.created_at,p.approved_at,p.claimed_at
        from herco_private.point_receipts p where p.member_id=member order by p.created_at desc,p.id desc limit 50) x)
  );
end;
$$;
revoke all on function public.herco_my_points() from public,anon,authenticated;
grant execute on function public.herco_my_points() to authenticated;

notify pgrst,'reload schema';
commit;
