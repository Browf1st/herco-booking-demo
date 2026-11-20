-- Demo operations UI data, keeping authoritative ledgers and staff grants.
begin;
alter table herco_private.point_rewards add column scope text not null default '' check(char_length(scope)<=200);
alter table herco_private.point_receipts add column reward_scope text not null default '' check(char_length(reward_scope)<=200), add column balance_after bigint, add column member_name text;
create sequence herco_private.point_receipt_reference_seq;
alter table herco_private.point_receipts add column reference text not null default ('AR-'||lpad(nextval('herco_private.point_receipt_reference_seq')::text,6,'0')) unique;
update herco_private.point_receipts p set balance_after=(select coalesce(sum(e.amount),0) from herco_private.point_entries e where e.member_id=p.member_id and (e.created_at,e.id)<=(select r.created_at,r.id from herco_private.point_entries r where r.receipt_id=p.id)),member_name=coalesce((select nullif(c.display_name,'') from public.herco_customer_profiles c where c.user_id=p.member_id),'HERCO customer');

create or replace function public.herco_redeem_points(reward_id uuid,request_id uuid)
returns uuid language plpgsql volatile security definer set search_path='' as $$
declare member uuid:=auth.uid(); existing herco_private.point_receipts; reward herco_private.point_rewards; receipt uuid; balance bigint;
begin
 if member is null or not exists(select 1 from auth.users u where u.id=member and u.email_confirmed_at is not null) then raise exception 'Sign in with a verified email.' using errcode='42501'; end if;
 if reward_id is null or request_id is null then raise exception 'Select a reward.' using errcode='22023'; end if;
 perform pg_advisory_xact_lock(72003,hashtext(member::text));
 select p.* into existing from herco_private.point_receipts p where p.member_id=member and p.request_id=herco_redeem_points.request_id;
 if found then if existing.reward_id<>reward_id then raise exception 'Request ID already used.' using errcode='22023'; end if; return existing.id; end if;
 select r.* into reward from herco_private.point_rewards r where r.id=reward_id and r.enabled for share;
 if not found then raise exception 'That reward is unavailable.' using errcode='22023'; end if;
 select coalesce(sum(e.amount),0) into balance from herco_private.point_entries e where e.member_id=member;
 if balance<reward.cost then raise exception 'You need more points for this reward.' using errcode='23514'; end if;
 insert into herco_private.point_receipts(member_id,request_id,reward_id,reward_label,reward_scope,cost,balance_after,member_name)
 values(member,request_id,reward.id,reward.label,reward.scope,reward.cost,balance-reward.cost,coalesce((select nullif(c.display_name,'') from public.herco_customer_profiles c where c.user_id=member),'HERCO customer')) returning id into receipt;
 insert into herco_private.point_entries(member_id,actor_id,amount,reason,receipt_id) values(member,member,-reward.cost,'Redeemed '||reward.label,receipt);
 return receipt;
end $$;

create function public.herco_save_reward_details(reward_id uuid,reward_label text,reward_scope text,points_cost integer,active boolean)
returns uuid language plpgsql volatile security definer set search_path='' as $$
begin
 perform herco_private.check_point_staff('manageRewards');
 if reward_scope is null or char_length(reward_scope)>200 then raise exception 'Check reward scope.' using errcode='22023'; end if;
 perform public.herco_save_point_reward(reward_id,reward_label,points_cost,active);
 update herco_private.point_rewards set scope=btrim(reward_scope) where id=reward_id;
 return reward_id;
end $$;
revoke all on function public.herco_save_reward_details(uuid,text,text,integer,boolean) from public,anon,authenticated;
grant execute on function public.herco_save_reward_details(uuid,text,text,integer,boolean) to authenticated;

create function public.herco_staff_points_workspace(search_term text default '',selected_member uuid default null)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare result jsonb;
begin
 perform herco_private.check_point_staff(null);
 if search_term is null or char_length(search_term)>254 then raise exception 'Check member search.' using errcode='22023'; end if;
 result:=public.herco_staff_points();
 return result||jsonb_build_object(
 'members',(select coalesce(jsonb_agg(to_jsonb(m) order by m.balance desc,m.name,m.id),'[]'::jsonb) from
 (select u.id,coalesce(nullif(p.display_name,''),nullif(to_jsonb(u)->'raw_user_meta_data'->>'name',''),'HERCO customer') name,u.email,coalesce(p.mobile,'') phone,
 (select coalesce(sum(e.amount),0) from herco_private.point_entries e where e.member_id=u.id) balance
 from auth.users u left join public.herco_customer_profiles p on p.user_id=u.id where u.email_confirmed_at is not null and
 (search_term='' or position(lower(search_term) in lower(coalesce(p.display_name,'')||' '||u.email||' '||coalesce(p.mobile,'')||' '||u.id::text))>0)
 order by balance desc,u.id limit 500) m),
 'ledger',(select coalesce(jsonb_agg(to_jsonb(e) order by e.created_at desc,e.id desc),'[]'::jsonb) from
 (select e.id,e.amount,e.reason,e.created_at,coalesce(nullif(p.display_name,''),'Shop staff') actor
 from herco_private.point_entries e left join public.herco_customer_profiles p on p.user_id=e.actor_id where e.member_id=selected_member
 order by e.created_at desc,e.id desc limit 100) e),
 'receipts',(select coalesce(jsonb_agg(to_jsonb(r) order by r.created_at desc,r.id),'[]'::jsonb) from
 (select p.*,coalesce(nullif(c.display_name,''),p.member_name,'HERCO customer') customer_name,u.email customer_email,coalesce(c.mobile,'') customer_phone,
 coalesce(nullif(a.display_name,''),'Shop staff') approved_name,coalesce(nullif(b.display_name,''),'Shop staff') claimed_name
 from herco_private.point_receipts p join auth.users u on u.id=p.member_id left join public.herco_customer_profiles c on c.user_id=p.member_id
 left join public.herco_customer_profiles a on a.user_id=p.approved_by left join public.herco_customer_profiles b on b.user_id=p.claimed_by
 order by p.created_at desc,p.id limit 500) r));
end $$;
revoke all on function public.herco_staff_points_workspace(text,uuid) from public,anon,authenticated;
grant execute on function public.herco_staff_points_workspace(text,uuid) to authenticated;

create table herco_private.inventory_options(kind text not null check(kind in('unit','category')),name text not null check(char_length(btrim(name)) between 1 and 60),primary key(kind,name));
create unique index inventory_options_normalized on herco_private.inventory_options(kind,lower(btrim(name)));
alter table herco_private.inventory_options enable row level security;
revoke all on herco_private.inventory_options from public,anon,authenticated;
create table herco_private.inventory_option_events(actor_id uuid not null references auth.users(id),request_id uuid not null,input jsonb not null,recorded_at timestamptz not null default now(),primary key(actor_id,request_id));
alter table herco_private.inventory_option_events enable row level security;
revoke all on herco_private.inventory_option_events from public,anon,authenticated;

create function public.herco_inventory_options_write(request_id uuid,kind text,previous_name text,new_name text)
returns void language plpgsql volatile security definer set search_path='' as $$
declare prior jsonb; details jsonb:=jsonb_build_object('kind',kind,'previous',previous_name,'name',new_name);
  max_length integer:=(case when kind='unit' then 30 else 60 end);
begin
 perform herco_private.check_inventory_staff(true);
 if request_id is null or kind is null or kind not in('unit','category') or new_name is null or char_length(btrim(new_name)) not between 1 and max_length then raise exception 'Enter a valid unit or category.' using errcode='22023'; end if;
 perform pg_advisory_xact_lock(72015,hashtext(auth.uid()::text||request_id::text));
 select e.input into prior from herco_private.inventory_option_events e where e.actor_id=auth.uid() and e.request_id=herco_inventory_options_write.request_id;
 if found then if prior<>details then raise exception 'Request already used.' using errcode='22023'; end if; return; end if;
 perform pg_advisory_xact_lock(72016,hashtext(kind));
 if previous_name is not null and previous_name<>'' then
  if kind='unit' then update herco_private.stock_items set unit=btrim(new_name),revision=revision+1 where unit=previous_name;
  else update herco_private.stock_items set category=btrim(new_name),revision=revision+1 where category=previous_name; end if;
  delete from herco_private.inventory_options o where o.kind=herco_inventory_options_write.kind and o.name=previous_name;
 end if;
 insert into herco_private.inventory_options values(kind,btrim(new_name)) on conflict do nothing;
 insert into herco_private.inventory_option_events values(auth.uid(),request_id,details,now());
end $$;
revoke all on function public.herco_inventory_options_write(uuid,text,text,text) from public,anon,authenticated;
grant execute on function public.herco_inventory_options_write(uuid,text,text,text) to authenticated;

create function public.herco_inventory_workspace(history_from date,history_through date,history_item uuid default null)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare data jsonb;
begin
 perform herco_private.check_inventory_staff(false);
 if history_from is null or history_through is null or history_through<history_from or history_through-history_from>365 then raise exception 'Choose up to 366 days.' using errcode='22023'; end if;
 data:=public.herco_inventory();
 return data||jsonb_build_object('options',(select coalesce(jsonb_agg(to_jsonb(o) order by o.kind,o.name),'[]'::jsonb) from
 (select kind,name from herco_private.inventory_options union select 'unit',unit from herco_private.stock_items union select 'category',category from herco_private.stock_items where category<>'') o),
 'recent',(select coalesce(jsonb_agg(to_jsonb(h) order by h.recorded_at desc,h.request_id),'[]'::jsonb) from
 (select a.*,coalesce(nullif(c.display_name,''),'Shop staff') actor_name from herco_private.stock_activity a left join public.herco_customer_profiles c on c.user_id=a.actor_id
 where (history_item is null or a.stock_id=history_item) and (a.recorded_at at time zone 'Asia/Manila')::date between history_from and history_through
 order by a.recorded_at desc,a.request_id limit 1000) h));
end $$;
revoke all on function public.herco_inventory_workspace(date,date,uuid) from public,anon,authenticated;
grant execute on function public.herco_inventory_workspace(date,date,uuid) to authenticated;

alter table herco_private.staff_memberships add column display_name text not null default '' check(char_length(display_name)<=120);
create function public.herco_staff_access_ui()
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare data jsonb;
begin
 data:=public.herco_staff_access();
 return data||jsonb_build_object('members',(select coalesce(jsonb_agg(x.value||jsonb_build_object('name',coalesce(nullif(m.display_name,''),nullif(c.display_name,''),'HERCO staff'))),'[]'::jsonb)
 from jsonb_array_elements(data->'members') x(value) join herco_private.staff_memberships m on m.user_id=(x.value->>'userId')::uuid left join public.herco_customer_profiles c on c.user_id=m.user_id));
end $$;
create function public.herco_save_staff_access_ui(p_target_id uuid,p_email text,p_role text,p_enabled boolean,p_page_grants text[],p_action_grants text[],p_expected_revision integer,p_display_name text)
returns void language plpgsql volatile security definer set search_path='' as $$
declare target uuid; before_name text; after_state jsonb;
begin
 if p_display_name is null or char_length(btrim(p_display_name)) not between 1 and 120 then raise exception 'Enter a staff name.' using errcode='22023'; end if;
 perform public.herco_save_staff_access(p_target_id,p_email,p_role,p_enabled,p_page_grants,p_action_grants,p_expected_revision);
 select m.user_id,m.display_name into strict target,before_name from herco_private.staff_memberships m join auth.users u on u.id=m.user_id where case when p_target_id is null then lower(u.email)=lower(p_email) else m.user_id=p_target_id end for update of m;
 update herco_private.staff_memberships set display_name=btrim(p_display_name) where user_id=target returning to_jsonb(staff_memberships) into after_state;
 if before_name is distinct from btrim(p_display_name) then insert into herco_private.staff_access_audit(actor_id,target_id,previous_state,new_state) values(auth.uid(),target,jsonb_build_object('display_name',before_name),after_state); end if;
end $$;
revoke all on function public.herco_staff_access_ui(),public.herco_save_staff_access_ui(uuid,text,text,boolean,text[],text[],integer,text) from public,anon,authenticated;
grant execute on function public.herco_staff_access_ui(),public.herco_save_staff_access_ui(uuid,text,text,boolean,text[],text[],integer,text) to authenticated;
create table herco_private.ui_pricing_audit(actor_id uuid not null references auth.users(id),request_id uuid not null,before_value jsonb,after_value jsonb not null,recorded_at timestamptz not null default now(),primary key(actor_id,request_id));
alter table herco_private.ui_pricing_audit enable row level security;
revoke all on herco_private.ui_pricing_audit from public,anon,authenticated;
create function herco_private.valid_price_tree(value jsonb)
returns boolean language plpgsql immutable set search_path='' as $$
declare child jsonb;
begin
 if jsonb_typeof(value)='number' then return (value#>>'{}')::numeric between 0 and 21474836.47 and scale((value#>>'{}')::numeric)<=2;
 elsif jsonb_typeof(value)='object' then for child in select v from jsonb_each(value) e(k,v) loop if not herco_private.valid_price_tree(child) then return false; end if; end loop; return true;
 elsif jsonb_typeof(value)='array' then if jsonb_array_length(value)<>2 or jsonb_typeof(value->0)<>'number' or jsonb_typeof(value->1)<>'number' then return false; end if; return herco_private.valid_price_tree(value->0) and herco_private.valid_price_tree(value->1) and (value->>0)::numeric <= (value->>1)::numeric;
 end if; return false;
end $$;
revoke all on function herco_private.valid_price_tree(jsonb) from public,anon,authenticated;
create function public.herco_staff_ui_pricing()
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare grants text[]:=herco_private.pricing_grants();
begin return (select jsonb_build_object('config',p.config,'revision',p.revision,'canEdit','changePricing'=any(grants)) from herco_private.ui_pricing p where p.singleton); end $$;
create function public.herco_save_ui_pricing(request_id uuid,expected_revision integer,configuration jsonb)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare grants text[]:=herco_private.pricing_grants(); previous herco_private.ui_pricing; prior herco_private.ui_pricing_audit; saved jsonb;
begin
 if not ('changePricing'=any(grants)) then raise exception 'Pricing permission required.' using errcode='42501'; end if;
 if request_id is null or expected_revision is null or configuration is null or pg_column_size(configuration)>20000 or not configuration ?& array['ceramic','powder'] or not (configuration->'ceramic') ?& array['tiers','addons','listedAddons','premiumGloss'] or not (configuration->'powder') ?& array['parts','wheelRates','prismatic','extras','largeSwingarm'] or not herco_private.valid_price_tree(configuration) or not (configuration->'ceramic'->'tiers') ?& array['1799','1999','2499'] or not (configuration->'ceramic'->'addons') ?& array['Matte to Glossy','Inner coating','Graphene coating','Mags coating','Helmet coating','K3 bracket / crashguard removal','Decals removal'] or not (configuration->'ceramic'->'listedAddons') ?& array['Matte to Glossy','Inner coating','Graphene coating'] then raise exception 'Check the coating rates.' using errcode='22023'; end if;
 perform pg_advisory_xact_lock(72017,hashtext(auth.uid()::text||request_id::text));
 select * into prior from herco_private.ui_pricing_audit a where a.actor_id=auth.uid() and a.request_id=herco_save_ui_pricing.request_id;
 if found then if prior.after_value->'config'<>configuration then raise exception 'Request ID already used.' using errcode='22023'; end if; return prior.after_value; end if;
 select * into strict previous from herco_private.ui_pricing where singleton for update;
 if previous.revision<>expected_revision then raise exception 'Prices changed. Reload before editing.' using errcode='40001'; end if;
 update herco_private.ui_pricing set config=configuration,revision=revision+1 where singleton returning jsonb_build_object('config',config,'revision',revision) into saved;
 insert into herco_private.ui_pricing_audit values(auth.uid(),request_id,to_jsonb(previous),saved,now()); return saved;
end $$;
revoke all on function public.herco_staff_ui_pricing(),public.herco_save_ui_pricing(uuid,integer,jsonb) from public,anon,authenticated;
grant execute on function public.herco_staff_ui_pricing(),public.herco_save_ui_pricing(uuid,integer,jsonb) to authenticated;
notify pgrst,'reload schema';
commit;
