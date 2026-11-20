-- Isolated local/CI fixture only. Never use this file as a hosted seed.
begin;
insert into auth.users(id,email,email_confirmed_at) values
 ('10000000-0000-4000-8000-000000000001','reward-owner@example.test',now()),
 ('10000000-0000-4000-8000-000000000002','reward-opted@example.test',now()),
 ('10000000-0000-4000-8000-000000000003','reward-private@example.test',now());
insert into public.herco_customer_profiles(user_id,display_name,mobile,leaderboard_opt_in,leaderboard_alias) values
 ('10000000-0000-4000-8000-000000000001','My private name','',false,''),
 ('10000000-0000-4000-8000-000000000002','Hidden legal name','09000000000',true,'Shared rider'),
 ('10000000-0000-4000-8000-000000000003','Never shared','09000000001',false,'');
insert into herco_private.point_entries(member_id,actor_id,amount,reason) values
 ('10000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001',100,'Own ledger fixture'),
 ('10000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000002',200,'Other private ledger'),
 ('10000000-0000-4000-8000-000000000003','10000000-0000-4000-8000-000000000003',300,'Never shared ledger');
set local role authenticated;
select set_config('test.uid','10000000-0000-4000-8000-000000000001',true);
do $$
declare payload jsonb := public.herco_my_points();
begin
 if (payload->>'balance')::int<>100 or payload->>'memberName'<>'My private name' then raise exception 'Own points/profile incorrect'; end if;
 if payload->'ranking' @> '[{"name":"Shared rider","balance":200}]'::jsonb is not true then raise exception 'Opt-in alias absent'; end if;
 if payload::text like '%Hidden legal name%' or payload::text like '%09000000000%' or payload::text like '%reward-opted%' or payload::text like '%Never shared%' or payload::text like '%Other private ledger%' then
   raise exception 'Customer rewards exposed another member private data'; end if;
 if jsonb_array_length(payload->'ledger')<>1 then raise exception 'Customer ledger crossed ownership boundary'; end if;
end;
$$;
reset role;
set local role anon;
select public.herco_reward_preview();
do $$ begin
 begin perform public.herco_my_points(); raise exception 'Anonymous points access allowed';
 exception when insufficient_privilege then null; end;
end $$;
rollback;
