-- Owner decision 2026-11-28: don't cap the HERCO Points fan ranking at 500 members. The members list now returns up
-- to 5,000 verified members (a safety ceiling, not a 500 cut-off), so the ranking can be paged or shown in full.
-- Verbatim copy of herco_staff_points_workspace from 202611190035 except the members `limit 500` -> `limit 5000`.
create or replace function public.herco_staff_points_workspace(search_term text default '',selected_member uuid default null)
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
 order by balance desc,u.id limit 5000) m),
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
