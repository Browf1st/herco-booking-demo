begin;
insert into auth.users(id,email,email_confirmed_at) values('00000000-0000-4000-8000-000000000201','operations-owner@example.test',now()),('00000000-0000-4000-8000-000000000202','operations-customer@example.test',now());
insert into herco_private.staff_memberships(user_id,role,page_grants,action_grants) values('00000000-0000-4000-8000-000000000201','owner',array['HERCO Points','Inventory','Pricing'],array['managePoints','manageRewards','manageInventory','changePricing']);
select set_config('test.uid','00000000-0000-4000-8000-000000000201',true);
select set_config('test.aal','aal1',true);
set local role authenticated;
select public.herco_save_reward_details('00000000-0000-4000-8000-000000000203','Fixture reward','Small parts',10,true);
select public.herco_adjust_points('00000000-0000-4000-8000-000000000202',100,'Fixture grant','00000000-0000-4000-8000-000000000204');
select public.herco_inventory_options_write('00000000-0000-4000-8000-000000000205','unit',null,'Fixture ml');
select public.herco_inventory_options_write('00000000-0000-4000-8000-000000000205','unit',null,'Fixture ml');
do $$ begin
 if jsonb_array_length(public.herco_inventory_workspace(current_date,current_date)->'options')<1 then raise exception 'Missing inventory option'; end if;
 if jsonb_array_length(public.herco_staff_points_workspace('operations-customer',null)->'members')<>1 then raise exception 'Member search did not match verified customer'; end if;
end $$;
reset role;
select set_config('test.uid','00000000-0000-4000-8000-000000000202',true);
set local role authenticated;
select public.herco_redeem_points('00000000-0000-4000-8000-000000000203','00000000-0000-4000-8000-000000000206');
do $$ begin
 begin perform public.herco_inventory_options_write('00000000-0000-4000-8000-000000000207','unit',null,'Unauthorized');raise exception 'Customer changed inventory options'; exception when insufficient_privilege then null; end;
 begin perform public.herco_staff_points_workspace('',null);raise exception 'Customer read staff member directory'; exception when insufficient_privilege then null; end;
end $$;
reset role;
do $$ begin
 if not exists(select 1 from herco_private.point_receipts where member_id='00000000-0000-4000-8000-000000000202' and reward_scope='Small parts' and balance_after=90 and reference like 'AR-%') then raise exception 'Receipt scope/balance/reference snapshot missing'; end if;
 if (select count(*) from herco_private.inventory_option_events where request_id='00000000-0000-4000-8000-000000000205')<>1 then raise exception 'Options retry duplicated audit'; end if;
end $$;
-- Booking menu counters and the customer directory total follow page grants.
update herco_private.staff_memberships set page_grants=page_grants||array['Bookings','Customers'] where user_id='00000000-0000-4000-8000-000000000201';
select set_config('test.uid','00000000-0000-4000-8000-000000000201',true);
set local role authenticated;
do $$ declare counts jsonb:=public.herco_staff_pending_counts(); begin
 if not (counts ? 'bookings' and counts ? 'requests') then raise exception 'Pending counts missing'; end if;
 if not (public.herco_staff_customer_directory('',null) ? 'total') then raise exception 'Directory total missing'; end if;
end $$;
reset role;
select set_config('test.uid','00000000-0000-4000-8000-000000000202',true);
set local role authenticated;
do $$ begin
 begin perform public.herco_staff_pending_counts(); raise exception 'Customer read booking counters'; exception when insufficient_privilege then null; end;
end $$;
reset role;
rollback;
